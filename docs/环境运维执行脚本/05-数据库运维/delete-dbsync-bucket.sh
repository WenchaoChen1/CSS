#!/usr/bin/env bash
# 删除数据库 dump 中转桶 css-dbsync-<账号>（2026-08-03 拍板：临时桶用完即删桶）。
# restore-dump-via-gw.sh 收尾会自动删；本脚本是手动兜底（如收尾时桶被占用未删成）。
# 幂等：桶不存在 → 直接成功。安全：桶非空默认拒绝，需 --force 才连对象一起删。
# 用法：
#   bash delete-dbsync-bucket.sh           # 桶空则删，非空拒绝
#   bash delete-dbsync-bucket.sh --force   # 先清空对象再删桶（确认里面没有还要用的 dump！）
set -euo pipefail
REGION="us-east-1"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="css-dbsync-$ACCOUNT_ID"

if ! aws --region "$REGION" s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "桶不存在，无需删除: $BUCKET"
  exit 0
fi

COUNT=$(aws --region "$REGION" s3api list-objects-v2 --bucket "$BUCKET" --max-keys 1 \
  --query 'KeyCount' --output text)
if [ "$COUNT" != "0" ]; then
  if [ "${1:-}" = "--force" ]; then
    echo "桶非空，--force 清空对象…"
    aws --region "$REGION" s3 rm "s3://$BUCKET" --recursive --only-show-errors
  else
    echo "[拒绝] 桶非空（可能有恢复流程在用）。确认无用后加 --force 重跑。"
    aws --region "$REGION" s3 ls "s3://$BUCKET" --recursive | head -20
    exit 1
  fi
fi

aws --region "$REGION" s3 rb "s3://$BUCKET"
echo "已删除中转桶: $BUCKET"
