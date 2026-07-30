#!/usr/bin/env bash
# 创建/更新 ALB（⚠️ 计费 ~$16/月/个 + LCU）：系统访问规范（2026-07-28 拍板）——
# Web 一律走 ALB（配域名），应用机在私有子网无公网 IP；SSH 只经堡垒机；RDS 仅内网。
#
# 转发规则（本脚本自动配齐）：
#   :80 / :443  → 本环境应用机的前端容器 :80（SPA + 同源反代 /api /ws /notifications 到 backend nginx）
# WebSocket：ALB 原生支持 HTTP/1.1 Upgrade，本脚本把 idle_timeout 提到 3600s，
#            与前端 nginx 的 proxy_read_timeout 3600s 对齐，避免长连接被 60s 掐断。
#
# kafka-ui（:8085）→ ALB（2026-07-29 起默认开启）
#   历史：一开始不挂 ALB，因为容器 AUTH_TYPE=DISABLED 是裸奔的，而它能读到 sms_send topic 里的
#   2FA 验证码；当时想用 IP 白名单兜底，但本机 HTTP 出口是会漂移的代理 IP（实测 103.62.49.138 /
#   134.195.101.194 轮换），白名单时通时不通，遂撤下改走 SSH 隧道。
#   现在：infra.yml 已把 kafka-ui 切成 AUTH_TYPE=LOGIN_FORM，用 env 里本就存在的
#   SPRING_SECURITY_USER_NAME / SPRING_SECURITY_USER_PASSWORD 做登录，**有认证了才挂 ALB**。
#   仍想额外加一层 IP 限制：KAFKA_UI_CIDR=1.2.3.4/32 ./create-alb.sh test
#   完全不想暴露：NO_KAFKA_UI=1 ./create-alb.sh test（退回 SSH 隧道方案）
#
# 命名（2026-07-29 用户拍板）：**每环境一个 ALB**，名字就是环境名——css-test / css-uat / css-prod；
# ALB 与目标组都打两个标签：Group=css-non-prod|css-prod + CssEnv=css-<env>。
#
# 用法: ./create-alb.sh <test|uat|prod> [域名]
#   例: ./create-alb.sh test
#       CERT_ARN=arn:aws:acm:us-east-1:...:certificate/xxx ./create-alb.sh uat uat.example.com
# 前置: 01-vpc 已建（含 css-<组>-alb-sg）；06-ec2 对应环境应用机已建（目标按固定私网 IP 注册）。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: create-alb.sh <test|uat|prod> [域名]}"
HOST_NAME="${2:-}"
REGION="us-east-1"
KAFKA_UI_PORT=8085
# 默认把 kafka-ui 挂上 ALB（容器已有登录认证）；给了 KAFKA_UI_CIDR 则再叠一层来源 IP 限制；
# NO_KAFKA_UI=1 则完全不挂（退回 SSH 隧道）。
KAFKA_UI_CIDR="${KAFKA_UI_CIDR:-}"
NO_KAFKA_UI="${NO_KAFKA_UI:-}"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

case "$ENV_NAME" in
  test) VPC_NAME=css-non-prod; GROUP=css-non-prod; APP_IP=10.20.10.10
        SG_NAME=css-non-prod-alb-sg; APP_SG_NAME=css-non-prod-app-sg ;;
  uat)  VPC_NAME=css-non-prod; GROUP=css-non-prod; APP_IP=10.20.11.10
        SG_NAME=css-non-prod-alb-sg; APP_SG_NAME=css-non-prod-app-sg ;;
  prod) VPC_NAME=css-prod;     GROUP=css-prod;     APP_IP=10.10.10.10
        SG_NAME=css-prod-alb-sg;    APP_SG_NAME=css-prod-app-sg ;;
  *) echo "环境必须是 test|uat|prod"; exit 1 ;;
esac
ALB_NAME="css-$ENV_NAME"          # ALB 名字 = 环境名
TAGS="Key=Name,Value=$ALB_NAME Key=Group,Value=$GROUP Key=CssEnv,Value=css-$ENV_NAME"

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
PUB1=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-public-1a" --query 'Subnets[0].SubnetId')
PUB2=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-public-1b" --query 'Subnets[0].SubnetId')
SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
APP_SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$APP_SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
[ "$SG" != "None" ] || { echo "缺 $SG_NAME，先跑 01-vpc/create-vpc.sh $GROUP"; exit 1; }

# ---- 安全组：ALB 收公网 80/443；应用机的 80 只收 ALB ----
allow() { aws --region "$REGION" ec2 authorize-security-group-ingress "$@" >/dev/null 2>&1 || true; }
allow --group-id "$SG" --protocol tcp --port 80  --cidr 0.0.0.0/0
allow --group-id "$SG" --protocol tcp --port 443 --cidr 0.0.0.0/0
allow --group-id "$APP_SG" --protocol tcp --port 80  --source-group "$SG"
echo "安全组就绪: alb=$SG（80/443 公网）app=$APP_SG（80 仅来自 ALB）"
if [ -z "$NO_KAFKA_UI" ]; then
  if [ -n "$KAFKA_UI_CIDR" ]; then
    allow --group-id "$SG" --protocol tcp --port "$KAFKA_UI_PORT" --cidr "$KAFKA_UI_CIDR"
    echo "kafka-ui: ALB $KAFKA_UI_PORT 仅放行 $KAFKA_UI_CIDR（登录认证 + IP 双保险）"
  else
    allow --group-id "$SG" --protocol tcp --port "$KAFKA_UI_PORT" --cidr 0.0.0.0/0
    echo "kafka-ui: ALB $KAFKA_UI_PORT 对公网开放，靠容器的 LOGIN_FORM 登录保护"
  fi
  allow --group-id "$APP_SG" --protocol tcp --port "$KAFKA_UI_PORT" --source-group "$SG"
fi

ensure_tg() { # name port target-ip health-path
  local name=$1 port=$2 ip=$3 hp=$4 arn
  arn=$(awsq elbv2 describe-target-groups --names "$name" --query 'TargetGroups[0].TargetGroupArn' 2>/dev/null || echo None)
  if [ "$arn" = "None" ] || [ -z "$arn" ]; then
    arn=$(awsq elbv2 create-target-group --name "$name" --protocol HTTP --port "$port" \
      --vpc-id "$VPC_ID" --target-type ip \
      --health-check-path "$hp" --health-check-interval-seconds 30 \
      --healthy-threshold-count 2 --unhealthy-threshold-count 5 \
      --matcher HttpCode=200-399 \
      --tags $TAGS --query 'TargetGroups[0].TargetGroupArn')
    echo "目标组创建: $name → $ip:$port（健康检查 $hp）" >&2
  fi
  # 长连接（WebSocket）：注销延迟调小，粘性关闭（SPA 无状态）
  aws --region "$REGION" elbv2 modify-target-group-attributes --target-group-arn "$arn" \
    --attributes Key=deregistration_delay.timeout_seconds,Value=30 >/dev/null 2>&1 || true
  aws --region "$REGION" elbv2 register-targets --target-group-arn "$arn" --targets "Id=$ip,Port=$port" >/dev/null
  echo "$arn"
}

ALB=$(awsq elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
if [ "$ALB" = "None" ] || [ -z "$ALB" ]; then
  ALB=$(awsq elbv2 create-load-balancer --name "$ALB_NAME" --type application --scheme internet-facing \
    --subnets "$PUB1" "$PUB2" --security-groups "$SG" \
    --tags $TAGS --query 'LoadBalancers[0].LoadBalancerArn')
  echo "ALB 创建: $ALB_NAME（等待 active…）"
  aws --region "$REGION" elbv2 wait load-balancer-available --load-balancer-arns "$ALB"
else
  echo "ALB 复用: $ALB_NAME"
fi
# WebSocket 长连接：idle timeout 与前端 nginx proxy_read_timeout(3600s) 对齐
aws --region "$REGION" elbv2 modify-load-balancer-attributes --load-balancer-arn "$ALB" \
  --attributes Key=idle_timeout.timeout_seconds,Value=3600 >/dev/null

# ---- 目标组：本环境前端（kafka-ui 仅在显式给了 KAFKA_UI_CIDR 时才建）----
TG_FE=$(ensure_tg "css-$ENV_NAME-fe-tg" 80 "$APP_IP" /)
TG_KUI=""
# kafka-ui 的健康检查用 /actuator/health（Spring Boot 端点，开了登录也不需要鉴权）；
# 根路径 / 在 LOGIN_FORM 模式下会 302 跳登录页，matcher 已含 3xx 故也能通过，但用 health 更准确。
[ -z "$NO_KAFKA_UI" ] && TG_KUI=$(ensure_tg "css-$ENV_NAME-kafkaui-tg" "$KAFKA_UI_PORT" "$APP_IP" /actuator/health)

ensure_listener() { # port default-tg [cert-arn]
  local port=$1 tg=$2 cert="${3:-}" arn args=()
  arn=$(awsq elbv2 describe-listeners --load-balancer-arn "$ALB" --query "Listeners[?Port==\`$port\`]|[0].ListenerArn")
  if [ "$arn" = "None" ] || [ -z "$arn" ]; then
    if [ -n "$cert" ]; then
      args=(--protocol HTTPS --certificates "CertificateArn=$cert" --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06)
    else
      args=(--protocol HTTP)
    fi
    arn=$(awsq elbv2 create-listener --load-balancer-arn "$ALB" --port "$port" "${args[@]}" \
      --default-actions "Type=forward,TargetGroupArn=$tg" --query 'Listeners[0].ListenerArn')
    echo "监听器创建: :$port" >&2
  fi
  echo "$arn"
}
L80=$(ensure_listener 80 "$TG_FE")
[ -n "${CERT_ARN:-}" ] && ensure_listener 443 "$TG_FE" "$CERT_ARN" >/dev/null
[ -n "$TG_KUI" ] && ensure_listener "$KAFKA_UI_PORT" "$TG_KUI" >/dev/null

# 每环境独立 ALB，无需 Host 分流；域名只用于提示 CNAME 与证书

DNS=$(awsq elbv2 describe-load-balancers --load-balancer-arns "$ALB" --query 'LoadBalancers[0].DNSName')
echo ""
echo "===== $ALB_NAME 就绪 ====="
echo "系统入口:  http://$DNS/            （前端 SPA；/api /ws /notifications 由前端 nginx 同源反代到后端）"
if [ -n "$TG_KUI" ]; then
  echo "kafka-ui:  http://$DNS:$KAFKA_UI_PORT/   （登录：env 里的 SPRING_SECURITY_USER_NAME / _PASSWORD）"
  [ -n "$KAFKA_UI_CIDR" ] && echo "           来源限制: $KAFKA_UI_CIDR"
  echo "           用途：Topics → sms_send 看 2FA 验证码"
else
  echo "kafka-ui:  未挂 ALB——经堡垒机隧道访问："
  echo "           ssh -i ~/.ssh/css-non-prod-gw.pem -N -L 8085:$APP_IP:8085 ec2-user@3.225.148.166 后开 http://localhost:8085"
fi
echo ""
echo "下一步："
echo "  1) DNS 把 ${HOST_NAME:-<你的域名>} CNAME 到 $DNS；ACM 出证书后 CERT_ARN=... 重跑本脚本补 443"
echo "  2) 前端 VITE_WS_BASE_URL / VITE_API_BASE_URL 指向该域名后【重新构建前端镜像】（VITE_* 是构建期烤入）"
echo "  3) ALB 稳定后收掉过渡通道：网关机 nginx 反代与 gw-sg 的 80/8080、app-sg 来自 gw 的 80"
echo "  4) 目标健康检查：EC2 控制台 → Target groups → css-*-fe-tg → Targets 应为 healthy（需容器已起）"
