#!/usr/bin/env bash
# 清空【新账号】某环境的 S3 应用桶（2026-08-04 新增，S3 迁移流程的配套）
#
# ⚠️⚠️ 【一次性脚本，已用完】2026-08-04 用户明确：清桶只此一次（test 桶那 102 个带废弃 `us-east-1/`
#   前缀的遗留对象，07-29 从已退役旧桶 sync 来、库内零引用），**此后一律只做增量同步、不再清桶**
#   —— 20 天后彻底迁移也是"把没同步的补上"（migrate-s3-to-new.sh / clone-env-bucket.sh 都是增量幂等的）。
#   保留本脚本仅为留档与极端情况兜底（如某桶被写脏需重来）；日常流程【不要】用它。
#
# ⚠️ 破坏性操作，三重保护：默认 dry-run 只列不删；实删要显式 --yes；prod 额外要求手输环境名。
# ⚠️ 只删对象，不删桶本身（桶由 css-terraform 管，`prevent_destroy` + `force_destroy=false`）。
#
# 用法:
#   ./purge-new-bucket.sh <test|uat|prod|dev>              # 预演：只统计/列样本
#   ./purge-new-bucket.sh <test|uat|prod|dev> --yes        # 实际清空
#   ./purge-new-bucket.sh test --yes --prefix us-east-1/   # 只清指定前缀
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"; shift || true
case "$ENV_NAME" in test|uat|prod|dev) ;; *) echo "用法: $0 <test|uat|prod|dev> [--yes] [--prefix 前缀]"; exit 1 ;; esac

GO=0; PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) GO=1 ;;
    --prefix) PREFIX="$2"; shift ;;
    *) echo "[FAIL] 未知参数: $1"; exit 1 ;;
  esac
  shift
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[ "$ACCOUNT_ID" != "021213872872" ] || { echo "[FAIL] 当前凭证是【老账号】，本脚本只清新账号的桶"; exit 1; }
BUCKET="css-${ENV_NAME}-${ACCOUNT_ID}"

echo "===== 清空新账号 S3 桶 ====="
echo "桶: s3://$BUCKET${PREFIX:+/$PREFIX}｜账号 $ACCOUNT_ID"

STAT=$(aws s3api list-objects-v2 --bucket "$BUCKET" ${PREFIX:+--prefix "$PREFIX"} \
  --output json --query '{n:length(Contents||`[]`),b:sum(Contents[].Size||`[0]`)}' 2>/dev/null || echo '{"n":0,"b":0}')
echo "当前对象: $STAT"
aws s3 ls "s3://$BUCKET/${PREFIX}" --recursive 2>/dev/null | head -5 | sed 's/^/  样本: /' || true

if [ "$GO" != 1 ]; then
  echo "===== 预演结束（未删除）。确认后加 --yes 实际清空 ====="
  exit 0
fi

if [ "$ENV_NAME" = "prod" ]; then
  printf '⚠️  这是【生产桶】，输入 prod 确认清空: '; read -r c
  [ "$c" = "prod" ] || { echo "已取消"; exit 1; }
fi

# 库里若已有指向本桶的 URL，清空会造成 404——只提示不阻断（迁移流程里通常是先清后同步再改 URL）
echo "[提示] 若库内已有指向本桶的 file_url，清空后那些文件会 404；迁移顺序应为：清桶 → 同步 → 改 URL"

aws s3 rm "s3://$BUCKET/${PREFIX}" --recursive --only-show-errors
LEFT=$(aws s3api list-objects-v2 --bucket "$BUCKET" ${PREFIX:+--prefix "$PREFIX"} --output json --query 'length(Contents||`[]`)' 2>/dev/null || echo 0)
echo "[OK] 已清空，剩余对象: $LEFT"
echo "下一步: ./migrate-s3-to-new.sh $ENV_NAME --dry-run"
