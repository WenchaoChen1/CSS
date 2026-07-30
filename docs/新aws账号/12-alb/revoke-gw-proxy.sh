#!/usr/bin/env bash
# 收掉网关机的 Web 过渡通道（ALB 接管后执行）：
#   1) 撤销 gw-sg 上给管理 IP 开的 80 / 8080（那是 ALB 之前用网关机 nginx 反代 test/uat 的临时口子）
#   2) 撤销 app-sg 上"来自 gw-sg 的 80"（应用机的 Web 端口此后只收 ALB）
#   3) 停用并禁用网关机上的 nginx（堡垒 22 与 NAT 出网不受影响）
# 收完后网关机只保留两件事：SSH 跳板（22，仅管理 IP）+ NAT 回程（VPC 内网段全协议）。
# 幂等。用法: ./revoke-gw-proxy.sh <nonprod|prod>
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

GROUP="${1:?用法: revoke-gw-proxy.sh <nonprod|prod>}"
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

case "$GROUP" in
  nonprod) VPC_NAME=css-non-prod; GW_SG_NAME=css-non-prod-gw-sg; APP_SG_NAME=css-non-prod-app-sg; GW_INST=css-non-prod-gw ;;
  prod)    VPC_NAME=css-prod;     GW_SG_NAME=css-prod-bastion-sg; APP_SG_NAME=css-prod-app-sg; GW_INST=css-prod-bastion ;;
  *) echo "未知组"; exit 1 ;;
esac

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
GW_SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$GW_SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
APP_SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$APP_SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')

for port in 80 8080; do
  for cidr in $(awsq ec2 describe-security-group-rules --filters "Name=group-id,Values=$GW_SG" \
        --query "SecurityGroupRules[?!IsEgress && FromPort==\`$port\` && CidrIpv4!=null].CidrIpv4" 2>/dev/null); do
    [ "$cidr" = "None" ] && continue
    aws --region "$REGION" ec2 revoke-security-group-ingress --group-id "$GW_SG" --protocol tcp --port "$port" --cidr "$cidr" >/dev/null 2>&1 \
      && echo "已撤销 $GW_SG_NAME 入站: $port ← $cidr"
  done
done
aws --region "$REGION" ec2 revoke-security-group-ingress --group-id "$APP_SG" --protocol tcp --port 80 --source-group "$GW_SG" >/dev/null 2>&1 \
  && echo "已撤销 $APP_SG_NAME 入站: 80 ← $GW_SG_NAME（Web 此后只收 ALB）" || echo "$APP_SG_NAME 无来自网关的 80 规则（已是目标状态）"

# 停网关机 nginx（经 SSM，不需要 SSH）
ID=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=$GW_INST" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId')
if [ "$ID" != "None" ] && [ -n "$ID" ]; then
  CID=$(awsq ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
    --comment "disable gw nginx proxy" \
    --parameters 'commands=["systemctl disable --now nginx 2>/dev/null || echo nginx 未安装/已停; rm -f /etc/nginx/conf.d/css.conf; systemctl is-active nginx || echo nginx: inactive; systemctl is-active css-nat.service && echo NAT: still active"]' \
    --query 'Command.CommandId')
  for i in $(seq 1 24); do
    ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query Status 2>/dev/null || echo Pending)
    case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 5
  done
  echo "网关机 nginx: $ST"
  awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardOutputContent 2>/dev/null || true
fi

echo ""
echo "===== 过渡通道已收 ====="
echo "网关机现在只剩：22（仅管理 IP，SSH 跳板）+ VPC 内网段全协议（NAT 回程，私有子网出网必需）"
echo "Web 入口唯一化：ALB css-<env> → 应用机 :80"
