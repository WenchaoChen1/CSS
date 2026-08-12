#!/usr/bin/env bash
# 把一个环境应用桶的对象整体同步到另一个环境的应用桶（S3 服务端复制，不经本机流量）。
# 典型用途：新环境的库数据是源环境副本时，file_url 引用的对象也要有一份——
#   2026-08-07 support-ref 建环境：css-uat-582797602427 → css-support-ref-582797602427，
#   配合 rewrite-file-urls.sh <env> --old-base <源桶前缀> 完成"数据 + 文件 + URL"三件套。
# 幂等：aws s3 sync 只复制缺失/更新的对象，重跑零副作用；不带 --delete，绝不删目标桶已有对象。
# 用法: ./sync-s3-env-bucket.sh <源env> <目标env> [--dry-run]
#   例: ./sync-s3-env-bucket.sh uat support-ref
set -euo pipefail

SRC_ENV="${1:?用法: sync-s3-env-bucket.sh <源env> <目标env> [--dry-run]}"
DST_ENV="${2:?缺目标环境}"
DRY="${3:-}"
for e in "$SRC_ENV" "$DST_ENV"; do
  case "$e" in test|uat|support-ref|support-demo|prod) ;; *) echo "[FAIL] 未知环境 $e（test|uat|support-ref|support-demo|prod）"; exit 1 ;; esac
done
[ "$SRC_ENV" != "$DST_ENV" ] || { echo "[FAIL] 源与目标相同"; exit 1; }
[ "$DST_ENV" = "prod" ] && { printf '⚠️  目标是【生产桶】，输入 prod 确认: '; read -r c; [ "$c" = "prod" ] || { echo "已取消"; exit 1; }; }

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text | tr -d '\r')"
SRC="s3://css-${SRC_ENV}-${ACCOUNT_ID}"
DST="s3://css-${DST_ENV}-${ACCOUNT_ID}"
ARGS=(--only-show-errors)
[ "$DRY" = "--dry-run" ] && ARGS+=(--dryrun)

echo "===== S3 桶同步: $SRC → $DST $([ "$DRY" = "--dry-run" ] && echo '【DRY-RUN】') ====="
aws s3 sync "$SRC" "$DST" "${ARGS[@]}"

echo "===== 同步后对象数核对 ====="
for b in "$SRC" "$DST"; do
  echo -n "$b : "
  aws s3 ls "$b" --recursive --summarize | grep 'Total Objects' | tr -d '\r'
done
echo "提醒: 库里 URL 的改写用 rewrite-file-urls.sh $DST_ENV --old-base 'https://s3.us-east-1.amazonaws.com/css-${SRC_ENV}-${ACCOUNT_ID}/'"
