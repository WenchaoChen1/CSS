#!/usr/bin/env bash
# 删除 RDS 实例（默认先打最终快照兜底，快照名 <id>-final-<日期>）。
# 用法: ./delete-rds.sh <实例标识> [--no-snapshot]
# ⚠️ 删除不可逆（除快照外）；有删除保护的实例会先解除。
set -euo pipefail
DB_ID="${1:?用法: delete-rds.sh <实例标识> [--no-snapshot]}"
REGION="us-east-1"
SNAP="${2:-}"

aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null \
  || { echo "实例不存在: $DB_ID"; exit 1; }

# 解除删除保护（如有）
PROT=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].DeletionProtection' --output text | tr -d '\r')
if [ "$PROT" = "True" ]; then
  aws rds modify-db-instance --region "$REGION" --db-instance-identifier "$DB_ID" \
    --no-deletion-protection --apply-immediately >/dev/null
  echo "已解除删除保护"
fi

if [ "$SNAP" = "--no-snapshot" ]; then
  aws rds delete-db-instance --region "$REGION" --db-instance-identifier "$DB_ID" \
    --skip-final-snapshot >/dev/null
  echo "删除中（无最终快照）: $DB_ID"
else
  FINAL="$DB_ID-final-$(date +%Y%m%d)"
  aws rds delete-db-instance --region "$REGION" --db-instance-identifier "$DB_ID" \
    --final-db-snapshot-identifier "$FINAL" >/dev/null
  echo "删除中，最终快照: $FINAL（确认不需要后可在控制台删快照省存储费）"
fi
echo "等待删除完成（约 5-15 分钟）..."
aws rds wait db-instance-deleted --region "$REGION" --db-instance-identifier "$DB_ID"
echo "===== 已删除: $DB_ID ====="
