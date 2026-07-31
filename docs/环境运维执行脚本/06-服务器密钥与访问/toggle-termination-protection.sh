#!/usr/bin/env bash
# 开/关 EC2 终止保护（disable_api_termination）。
# 用途：Terraform 重建实例（replace）前必须先关保护——TF 的 destroy 不会自动解除，直接 apply 会报错；
#       重建出的新实例由 Terraform 自动带保护，无需再开。也可用于临时需要终止某实例的场景。
# 用法: ./toggle-termination-protection.sh <实例ID|名称> <on|off>
#   例: ./toggle-termination-protection.sh css-test-app off   # 重建前
set -euo pipefail

TARGET="${1:?用法: toggle-termination-protection.sh <实例ID|Name标签> <on|off>}"
ACTION="${2:?第二个参数: on|off}"
REGION=us-east-1

if [[ "$TARGET" == i-* ]]; then
  ID="$TARGET"
else
  ID=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=$TARGET" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
  [ "$ID" != "None" ] && [ -n "$ID" ] || { echo "找不到名为 $TARGET 的实例"; exit 1; }
fi

case "$ACTION" in
  on)  aws ec2 modify-instance-attribute --region "$REGION" --instance-id "$ID" --disable-api-termination ;;
  off) aws ec2 modify-instance-attribute --region "$REGION" --instance-id "$ID" --no-disable-api-termination ;;
  *) echo "第二个参数只能是 on|off"; exit 1 ;;
esac

NOW=$(aws ec2 describe-instance-attribute --region "$REGION" --instance-id "$ID" \
  --attribute disableApiTermination --query 'DisableApiTermination.Value' --output text)
echo "$ID 终止保护现在为: $NOW（$([ "$NOW" = "True" ] && echo 受保护 || echo 可终止——记得重建后确认 TF 已恢复保护)）"
