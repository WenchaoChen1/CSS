#!/usr/bin/env bash
# 删除一台 EC2 实例并释放其关联 EIP（⚠️ 不可逆：根卷随实例销毁）。
# 典型用途：退役默认 VPC 时代的旧 test 机 css-non-prod（i-08e110b5a5425980d，2026-07-28）。
# 安全护栏：网关/堡垒机（css-non-prod-gw / css-prod-bastion）拒绝删除，防误伤私有子网出网通道。
# 用法: ./delete-ec2.sh <实例ID或Name标签> yes     （第二参必须字面量 yes，防手滑）
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

TARGET="${1:?用法: delete-ec2.sh <实例ID或Name标签> yes}"
CONFIRM="${2:-}"
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

# ---- 解析实例（ID 或 Name 标签）----
if [[ "$TARGET" == i-* ]]; then
  FILTER=(--instance-ids "$TARGET")
else
  FILTER=(--filters "Name=tag:Name,Values=$TARGET" "Name=instance-state-name,Values=pending,running,stopping,stopped")
fi
read -r ID NAME TYPE VPC PUB < <(awsq ec2 describe-instances "${FILTER[@]}" \
  --query 'Reservations[0].Instances[0].[InstanceId,Tags[?Key==`Name`]|[0].Value,InstanceType,VpcId,PublicIpAddress]' || echo "None")
[ "${ID:-None}" != "None" ] || { echo "找不到实例: $TARGET"; exit 1; }

case "$NAME" in
  css-non-prod-gw|css-prod-bastion)
    echo "拒绝: $NAME 是网关/堡垒机（私有子网出网与运维通道），不允许用本脚本删除"; exit 1 ;;
esac

echo "将删除: $ID  Name=$NAME  $TYPE  vpc=$VPC  公网=$PUB"
[ "$CONFIRM" = "yes" ] || { echo "未确认（第二参数需为 yes），已取消"; exit 1; }

# ---- 释放关联 EIP（不释放会按闲置 EIP 计费）----
read -r ALLOC ASSOC EIP < <(awsq ec2 describe-addresses \
  --filters "Name=instance-id,Values=$ID" \
  --query 'Addresses[0].[AllocationId,AssociationId,PublicIp]' || echo "None")
if [ "${ALLOC:-None}" != "None" ]; then
  aws --region "$REGION" ec2 disassociate-address --association-id "$ASSOC"
  aws --region "$REGION" ec2 release-address --allocation-id "$ALLOC"
  echo "EIP 已释放: $EIP ($ALLOC)"
fi

# ---- 终止实例（根卷 DeleteOnTermination 随实例删除）----
aws --region "$REGION" ec2 terminate-instances --instance-ids "$ID" >/dev/null
echo "终止中: $ID …"
aws --region "$REGION" ec2 wait instance-terminated --instance-ids "$ID"
echo "===== 已删除 $NAME ($ID)，EIP 已释放 ====="
echo "提醒: 其安全组/密钥对未删除（复用无害）；若该机曾是 SSM 部署目标，检查 CssEnv 标签映射是否需要更新"
