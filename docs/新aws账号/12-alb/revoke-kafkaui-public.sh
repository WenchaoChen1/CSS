#!/usr/bin/env bash
# 回收 kafka-ui 的公网暴露（ALB :8085 监听器 + 目标组 + 两条安全组规则）。
# 理由：kafka-ui 无认证且能读到 sms_send 里的 2FA 验证码；本机 HTTP 出口是漂移的代理 IP，
#      IP 白名单既不安全也不可靠。正确访问方式 = 经堡垒机 SSH 隧道（见文末）。
# 幂等：不存在的对象直接跳过。用法: ./revoke-kafkaui-public.sh <test|uat|prod>
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: revoke-kafkaui-public.sh <test|uat|prod>}"
REGION="us-east-1"
PORT=8085
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

# 2026-07-29：ALB 改为每环境一个（名字=环境名），旧的共享 css-nonprod-alb 已删除
case "$ENV_NAME" in
  test|uat) ALB_NAME="css-$ENV_NAME"; SG_NAME=css-non-prod-alb-sg; APP_SG_NAME=css-non-prod-app-sg; VPC_NAME=css-non-prod ;;
  prod)     ALB_NAME=css-prod;        SG_NAME=css-prod-alb-sg;     APP_SG_NAME=css-prod-app-sg;     VPC_NAME=css-prod ;;
  *) echo "环境必须是 test|uat|prod"; exit 1 ;;
esac
TG_NAME="css-$ENV_NAME-kafkaui-tg"

ALB=$(awsq elbv2 describe-load-balancers --names "$ALB_NAME" --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
if [ "$ALB" != "None" ] && [ -n "$ALB" ]; then
  L=$(awsq elbv2 describe-listeners --load-balancer-arn "$ALB" --query "Listeners[?Port==\`$PORT\`]|[0].ListenerArn")
  if [ "$L" != "None" ] && [ -n "$L" ]; then
    aws --region "$REGION" elbv2 delete-listener --listener-arn "$L"
    echo "已删监听器: :$PORT"
  else
    echo "无 :$PORT 监听器"
  fi
fi
TG=$(awsq elbv2 describe-target-groups --names "$TG_NAME" --query 'TargetGroups[0].TargetGroupArn' 2>/dev/null || echo None)
if [ "$TG" != "None" ] && [ -n "$TG" ]; then
  aws --region "$REGION" elbv2 delete-target-group --target-group-arn "$TG" && echo "已删目标组: $TG_NAME"
fi

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
APP_SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$APP_SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
# ALB SG 上所有指向 8085 的 CIDR 规则；应用机 SG 上"来自 ALB 的 8085"
for cidr in $(awsq ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG" \
      --query "SecurityGroupRules[?!IsEgress && FromPort==\`$PORT\`].CidrIpv4" 2>/dev/null); do
  [ "$cidr" = "None" ] && continue
  aws --region "$REGION" ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port "$PORT" --cidr "$cidr" >/dev/null 2>&1 \
    && echo "已撤销 alb-sg 入站: $PORT ← $cidr"
done
aws --region "$REGION" ec2 revoke-security-group-ingress --group-id "$APP_SG" --protocol tcp --port "$PORT" --source-group "$SG" >/dev/null 2>&1 \
  && echo "已撤销 app-sg 入站: $PORT ← alb-sg" || true

echo "===== kafka-ui 公网暴露已回收 ====="
echo "改用堡垒机隧道（本机执行，保持窗口不关）："
echo "  ssh -i ~/.ssh/wenchao -L 8085:10.20.10.10:8085 ec2-user@3.225.148.166"
echo "  然后浏览器打开 http://localhost:8085  → Topics → sms_send 看 2FA 验证码"
