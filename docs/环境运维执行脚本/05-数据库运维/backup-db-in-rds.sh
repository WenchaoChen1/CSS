#!/usr/bin/env bash
# 在【同一台 RDS 实例内】把某环境的业务库复制成 backup_ 前缀的留档库（不出实例、不落文件）。
#
#   css-<env>-main → backup_<日期>_<env>_main      css-<env>-ocr → backup_<日期>_<env>_ocr
#
# 典型用途：重建/灌数前给现库留一份可回滚的库内快照（库名规范：英文、backup_ 前缀放最前，
# 与 restore-old-env-backup.sh 的 backup_<日期>_old_* 同族）。
# 链路：堡垒机上 pg_dump -Fc | pg_restore（流式、无中间文件），源/目标都是同一 RDS。
# 凭证：自动从 Secrets Manager 取 master（rds! 前缀 secret，7 天轮换所以必须动态取）——
#       建库需要 CREATEDB 属性，css_ops 虽在 rds_superuser 组但属性不随成员继承，普通账号建不了库。
#
# 用法:
#   ./backup-db-in-rds.sh <test|uat|support-ref|support-demo|support-sync|prod> [日期标签YYYYMMDD]
# 例:
#   ./backup-db-in-rds.sh test            # 建 backup_<今天>_test_main / _ocr
#   ONLY=main ./backup-db-in-rds.sh uat 20260901
#
# 可选环境变量:
#   ONLY=main|ocr         只复制其中一个库（默认 main+ocr 都复制）
#   DEV_KEY=<私钥路径>     用开发者自己的临时钥代替管理员钥
#
# 注意：
# - 目标 backup_ 库已存在时中止（绝不覆盖既有留档）；留档库用完请 DROP，别让实例膨胀。
# - 留档库 owner=postgres，不授予应用账号权限；css_dev 只读需要时重跑 make-css-dev-readonly.sh 补授权。
# - 复制期间源库的并发写不会被阻塞（pg_dump 快照一致性），但业务高峰期跑会拖慢实例。
set -uo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: backup-db-in-rds.sh <test|uat|support-ref|support-demo|support-sync|prod> [YYYYMMDD]}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;; esac
DATE_TAG="${2:-$(date +%Y%m%d)}"
REGION=us-east-1
ENV_TAG="${ENV_NAME//-/_}"   # 库名里环境连字符换下划线（backup_20260813_support_ref_main）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_DIR="$(cd "$SCRIPT_DIR/../../../deploy-env/ssh" && pwd)"
case "$ENV_NAME" in
  test|uat|support-ref|support-demo|support-sync) BASTION_IP=3.225.148.166; KEY="$SSH_DIR/css-non-prod-gw.pem"; RDS_ID=css-non-prod ;;
  prod)                                           BASTION_IP=34.225.237.45; KEY="$SSH_DIR/css-prod-bastion";    RDS_ID=css-prod ;;
esac
KEY="${DEV_KEY:-$KEY}"
[ -f "$KEY" ] || { echo "[FATAL] 找不到私钥 $KEY"; exit 1; }

EP=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
       --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null | tr -d '\r')
[ -n "$EP" ] && [ "$EP" != "None" ] || { echo "[FATAL] 查不到 RDS $RDS_ID 的地址"; exit 1; }

# ---- master 凭证：Secrets Manager（rds! 前缀，随实例托管、7 天轮换）----
SECRET_ARN=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
               --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text 2>/dev/null | tr -d '\r')
[ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "None" ] || { echo "[FATAL] 实例 $RDS_ID 没有托管 master secret"; exit 1; }
SECRET_JSON=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$SECRET_ARN" \
                --query 'SecretString' --output text 2>/dev/null)
[ -n "$SECRET_JSON" ] || { echo "[FATAL] 取不到 master secret（IAM 权限？）"; exit 1; }

case "${ONLY:-both}" in
  main) TAGS=(main) ;;
  ocr)  TAGS=(ocr) ;;
  both) TAGS=(main ocr) ;;
  *)    echo "[FATAL] ONLY 只能是 main|ocr"; exit 1 ;;
esac

echo "===== 库内留档计划（$RDS_ID）====="
for TAG in "${TAGS[@]}"; do
  echo "  css-$ENV_NAME-$TAG  →  backup_${DATE_TAG}_${ENV_TAG}_${TAG}"
done

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20
          -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -i "$KEY")

FAIL=0
for TAG in "${TAGS[@]}"; do
  SRC_DB="css-$ENV_NAME-$TAG"
  DST_DB="backup_${DATE_TAG}_${ENV_TAG}_${TAG}"
  echo "--- $SRC_DB → $DST_DB …"
  {
    printf "export SECRET_JSON=%q EP=%q SRC_DB=%q DST_DB=%q\n" \
      "$SECRET_JSON" "$EP" "$SRC_DB" "$DST_DB"
    cat <<'REMOTE'
set -uo pipefail
command -v pg_dump >/dev/null || { echo "[FATAL] 堡垒机缺 pg 客户端：sudo dnf install -y postgresql16"; exit 1; }
command -v python3 >/dev/null || { echo "[FATAL] 堡垒机缺 python3"; exit 1; }
MUSER=$(python3 -c 'import json,os;print(json.loads(os.environ["SECRET_JSON"])["username"])') || exit 1
export PGPASSWORD="$(python3 -c 'import json,os;print(json.loads(os.environ["SECRET_JSON"])["password"])')" || exit 1
P() { psql -h "$EP" -p 5432 -U "$MUSER" -d postgres -v ON_ERROR_STOP=1 -tA "$@"; }

EXISTS=$(P -c "SELECT 1 FROM pg_database WHERE datname='$DST_DB'" | tr -d '[:space:]') \
  || { echo "[FATAL] 连不上 RDS（master 凭证/网络）"; exit 1; }
[ "${EXISTS:-}" != "1" ] || { echo "[FATAL] 目标库 $DST_DB 已存在，绝不覆盖既有留档——换日期标签或先 DROP"; exit 1; }
P -c "CREATE DATABASE \"$DST_DB\" ENCODING 'UTF8' TEMPLATE template0" >/dev/null \
  || { echo "[FATAL] 建库 $DST_DB 失败"; exit 1; }
echo "    已建库 $DST_DB"

RC=0
pg_dump --format=custom --no-owner --no-privileges -h "$EP" -p 5432 -U "$MUSER" -d "$SRC_DB" \
  | pg_restore --no-owner --no-privileges -h "$EP" -p 5432 -U "$MUSER" -d "$DST_DB" || RC=$?
echo "    pg_dump|pg_restore 退出码: $RC（0=干净；1=仅 warning 可接受）"
[ "$RC" -le 1 ] || { echo "[FATAL] pg_restore 硬失败（$RC），留档库 $DST_DB 不完整，勿使用"; exit 1; }

# 校验：两边 public 表数一致 + 目标库大小
SRC_TBL=$(psql -h "$EP" -p 5432 -U "$MUSER" -d "$SRC_DB" -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public'" | tr -d '[:space:]')
DST_TBL=$(psql -h "$EP" -p 5432 -U "$MUSER" -d "$DST_DB" -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public'" | tr -d '[:space:]')
SIZE=$(P -c "SELECT pg_size_pretty(pg_database_size('$DST_DB'))")
echo "    校验: 源表数=$SRC_TBL 目标表数=$DST_TBL 目标库大小=$SIZE"
[ -n "$SRC_TBL" ] && [ "$SRC_TBL" = "$DST_TBL" ] || { echo "[FATAL] 表数不一致，留档不完整"; exit 1; }
echo "    ✅ $DST_DB 完成"
REMOTE
  } | ssh "${SSH_OPTS[@]}" ec2-user@"$BASTION_IP" bash -s || FAIL=1
done

[ "$FAIL" = 0 ] || { echo "===== 有库留档失败，见上方日志 ====="; exit 1; }
echo "===== 库内留档完成 ====="
echo "提醒: 留档库含业务数据，用完 DROP；css_dev 需要读它时重跑 make-css-dev-readonly.sh。"
