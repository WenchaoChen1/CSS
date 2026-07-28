#!/usr/bin/env bash
# 创建 ALB（⚠️ 计费 ~$16/月/个）：系统访问规范（2026-07-28 拍板）——Web 一律走 ALB+域名，
# 应用机不暴露公网；ALB 就绪后应收掉网关机 nginx 的 80/8080 过渡通道（01-vpc 注释处两条 + 06-ec2 网关 nginx）。
#   nonprod → css-nonprod-alb：默认转发 test 机(10.20.10.10:80)；给出 uat 域名时按 Host 头分流 uat 机(10.20.11.10:80)
#   prod    → css-prod-alb：转发 prod 机(10.10.10.10:80)
# HTTPS：先在 ACM 申请并验证证书，再传 CERT_ARN 环境变量（无证书时只建 80 监听器）。
# 用法: ./create-alb.sh <nonprod|prod> [uat域名]     例: CERT_ARN=arn:aws:acm:... ./create-alb.sh nonprod uat.example.com
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

GROUP="${1:?用法: create-alb.sh <nonprod|prod> [uat域名]}"
UAT_HOST="${2:-}"
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

case "$GROUP" in
  nonprod) VPC_NAME=css-non-prod; ALB_NAME=css-nonprod-alb; SG_NAME=css-nonprod-alb-sg ;;
  prod)    VPC_NAME=css-prod;     ALB_NAME=css-prod-alb;    SG_NAME=css-prod-alb-sg ;;
  *) echo "未知组"; exit 1 ;;
esac

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
PUB1=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-public-1a" --query 'Subnets[0].SubnetId')
PUB2=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-public-1b" --query 'Subnets[0].SubnetId')
SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
[ "$SG" != "None" ] || { echo "缺 $SG_NAME，先跑 01-vpc/create-vpc.sh $GROUP"; exit 1; }

ensure_tg() { # name target-ip
  local name=$1 ip=$2 arn
  arn=$(awsq elbv2 describe-target-groups --names "$name" --query 'TargetGroups[0].TargetGroupArn' 2>/dev/null || echo None)
  if [ "$arn" = "None" ]; then
    arn=$(awsq elbv2 create-target-group --name "$name" --protocol HTTP --port 80 \
      --vpc-id "$VPC_ID" --target-type ip \
      --health-check-path / --health-check-interval-seconds 30 \
      --matcher HttpCode=200-399 \
      --tags Key=Group,Value="$VPC_NAME" --query 'TargetGroups[0].TargetGroupArn')
    echo "目标组创建: $name → $ip" >&2
  fi
  aws --region "$REGION" elbv2 register-targets --target-group-arn "$arn" --targets "Id=$ip,Port=80"
  echo "$arn"
}

ALB=$(awsq elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
if [ "$ALB" = "None" ]; then
  ALB=$(awsq elbv2 create-load-balancer --name "$ALB_NAME" --type application --scheme internet-facing \
    --subnets "$PUB1" "$PUB2" --security-groups "$SG" \
    --tags Key=Group,Value="$VPC_NAME" --query 'LoadBalancers[0].LoadBalancerArn')
  echo "ALB 创建: $ALB_NAME"
else
  echo "ALB 复用: $ALB_NAME"
fi

if [ "$GROUP" = "nonprod" ]; then
  TG_TEST=$(ensure_tg css-test-tg 10.20.10.10)
  DEFAULT_TG="$TG_TEST"
else
  DEFAULT_TG=$(ensure_tg css-prod-tg 10.10.10.10)
fi

ensure_listener() { # port [cert-arn]
  local port=$1 cert="${2:-}" arn args=()
  arn=$(awsq elbv2 describe-listeners --load-balancer-arn "$ALB" --query "Listeners[?Port==\`$port\`]|[0].ListenerArn")
  if [ "$arn" = "None" ] || [ -z "$arn" ]; then
    [ -n "$cert" ] && args=(--protocol HTTPS --certificates "CertificateArn=$cert" --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06) || args=(--protocol HTTP)
    arn=$(awsq elbv2 create-listener --load-balancer-arn "$ALB" --port "$port" "${args[@]}" \
      --default-actions "Type=forward,TargetGroupArn=$DEFAULT_TG" --query 'Listeners[0].ListenerArn')
    echo "监听器创建: :$port" >&2
  fi
  echo "$arn"
}
L80=$(ensure_listener 80)
[ -n "${CERT_ARN:-}" ] && ensure_listener 443 "$CERT_ARN"

# uat 按 Host 头分流（仅 nonprod 且给了域名）
if [ "$GROUP" = "nonprod" ] && [ -n "$UAT_HOST" ]; then
  TG_UAT=$(ensure_tg css-uat-tg 10.20.11.10)
  EXIST=$(awsq elbv2 describe-rules --listener-arn "$L80" --query "Rules[?Conditions[?Field=='host-header' && contains(Values,'$UAT_HOST')]]|[0].RuleArn")
  if [ "$EXIST" = "None" ] || [ -z "$EXIST" ]; then
    aws --region "$REGION" elbv2 create-rule --listener-arn "$L80" --priority 10 \
      --conditions "Field=host-header,Values=$UAT_HOST" \
      --actions "Type=forward,TargetGroupArn=$TG_UAT" >/dev/null
    echo "分流规则: Host=$UAT_HOST → uat"
  fi
fi

DNS=$(awsq elbv2 describe-load-balancers --load-balancer-arns "$ALB" --query 'LoadBalancers[0].DNSName')
echo "===== $ALB_NAME 就绪: http://$DNS ====="
echo "下一步: ① DNS 把域名 CNAME 到 $DNS；② ACM 证书就绪后 CERT_ARN=... 重跑本脚本加 443；"
echo "        ③ 收掉过渡通道——网关机 nginx 反代与 01-vpc 里 gw-sg 的 80/8080、app-sg 来自 gw 的 80 规则"
