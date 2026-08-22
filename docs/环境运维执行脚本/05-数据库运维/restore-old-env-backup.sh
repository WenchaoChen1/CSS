#!/usr/bin/env bash
# 把【老账号 021213872872】三个环境的数据库备份，恢复成【新账号非生产 RDS】上的**独立备份库**。
#
# 与同目录 restore-dump-via-gw.sh 的区别（为什么不复用它）：
#   restore-dump-via-gw.sh 是【环境投产】用的——目标库名硬编码 css-<env>-main/ocr，且带
#   --clean --if-exists，会**清空覆盖**正在用的 test/uat 库。本脚本是【留档快照】用的：
#   每次恢复到一个带日期后缀的**全新库**，不触碰任何现有环境库，也不接任何应用。
#
# 目标库命名（2026-08-03 规范：库名一律英文、backup_ 前缀放最前）：
#   backup_<YYYYMMDD>_old_<源环境>_main / backup_<YYYYMMDD>_old_<源环境>_ocr
#   `old` 标示「来自老账号」，避免与新账号的 css-test-main 等环境库混淆；全小写+下划线，SQL 无需引号。
#
# 通路：本地 dump → S3 中转桶 css-dbsync-<账号> → SSM 在网关机上 pg_restore（RDS 在私有子网，本地直连不了）。
#
# 用法: ./restore-old-env-backup.sh <dev|stage|preprod|all> [日期后缀 YYYYMMDD] [--to css-non-prod|css-prod]
#       ./restore-old-env-backup.sh --list [--to css-prod]   # 只列出 RDS 上现有的库，不做任何改动
#   日期后缀缺省取 dump 文件名里的日期；库已存在则跳过（要重建先手工 DROP，脚本不替你删数据）。
#   --to（2026-08-22 加，产品切换需要）：备份库建到哪个 RDS 实例，缺省 css-non-prod；
#   css-prod 时经 prod 堡垒机执行（css-gw-prod 角色有本实例 rds! secret 读取与 dbsync 桶只读）。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

REGION="us-east-1"

# ---- 目标实例：--to 参数抽取（其余参数原位保留）----
TARGET="css-non-prod"
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --to) shift; TARGET="${1:?--to 需要 css-non-prod|css-prod}" ;;
    *) ARGS+=("$1") ;;
  esac
  shift || true
done
set -- ${ARGS[@]+"${ARGS[@]}"}
case "$TARGET" in css-non-prod|css-prod) ;; *) echo "--to 只能是 css-non-prod|css-prod"; exit 1 ;; esac
RDS_ID="$TARGET"             # 缺省 css-non-prod（test/uat 共用实例）；--to css-prod 建到生产实例
GW_GROUP="$TARGET"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DUMP_ROOT="$ROOT/备份/数据库"

awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
[ "$ENDPOINT" != "None" ] && [ -n "$ENDPOINT" ] || { echo "[FATAL] RDS $RDS_ID 不存在"; exit 1; }

# 网关机用【控制面标签对】定位，不用 Name（Name 是可改展示名，改名曾把姊妹脚本搞失效过）
GW_ID=$(awsq ec2 describe-instances \
  --filters "Name=tag:Environment,Values=css-shared" "Name=tag:EnvironmentGroup,Values=$GW_GROUP" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' | awk '{print $1}')
[ -n "$GW_ID" ] && [ "$GW_ID" != "None" ] || { echo "[FATAL] 找不到 $GW_GROUP 组运行中的网关机"; exit 1; }

# ---- 在网关机上跑一段 shell，回显结果 ----
run_on_gw() {  # $1=远程脚本  $2=注释
  local params cmd_id st
  params=$( (python3 - "$1" 2>/dev/null || python - "$1") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["3600"]}))
PY
  )
  cmd_id=$(awsq ssm send-command --instance-ids "$GW_ID" --document-name AWS-RunShellScript \
    --comment "$2" --parameters "$params" --query 'Command.CommandId')
  while :; do
    st=$(awsq ssm get-command-invocation --command-id "$cmd_id" --instance-id "$GW_ID" --query Status 2>/dev/null || echo Pending)
    case "$st" in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 10
  done
  aws --region "$REGION" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$GW_ID" \
    --query 'StandardOutputContent' --output text | tr -d '\r'
  if [ "$st" != "Success" ]; then
    echo "[FATAL] SSM 执行失败（状态 $st）：" >&2
    aws --region "$REGION" ssm get-command-invocation --command-id "$cmd_id" --instance-id "$GW_ID" \
      --query 'StandardErrorContent' --output text | tr -d '\r' >&2
    return 1
  fi
}

PGENV="export PGPASSWORD=\$(aws secretsmanager get-secret-value --region $REGION --secret-id '$SECRET_ARN' --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"password\"])')"

# ---- --list：只看，不改 ----
if [ "${1:-}" = "--list" ]; then
  echo "RDS $RDS_ID ($ENDPOINT) 上的库："
  run_on_gw "set -euo pipefail
command -v psql >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1
$PGENV
psql -h $ENDPOINT -U postgres -d postgres -tAF'|' -c \"select datname, pg_size_pretty(pg_database_size(datname)) from pg_database where not datistemplate order by 1\"
echo '--- 磁盘余量 ---'
psql -h $ENDPOINT -U postgres -d postgres -tAc \"select pg_size_pretty(sum(pg_database_size(datname))) from pg_database\"" "list dbs on $RDS_ID"
  exit 0
fi

SRC="${1:?用法: restore-old-env-backup.sh <dev|stage|preprod|all> [YYYYMMDD]  |  --list}"
DATE_SUFFIX="${2:-}"
case "$SRC" in all) SRCS="dev stage preprod";; dev|stage|preprod) SRCS="$SRC";; *) echo "源环境只能是 dev|stage|preprod|all"; exit 1;; esac

ACCOUNT_ID=$(awsq sts get-caller-identity --query Account)
BUCKET="css-dbsync-$ACCOUNT_ID"
if ! aws --region "$REGION" s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws --region "$REGION" s3api create-bucket --bucket "$BUCKET" >/dev/null
  aws --region "$REGION" s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws --region "$REGION" s3api put-bucket-tagging --bucket "$BUCKET" \
    --tagging 'TagSet=[{Key=EnvironmentGroup,Value=css-non-prod},{Key=Environment,Value=css-shared},{Key=ManagedBy,Value=script-restore-old-env-backup}]'
  echo "中转桶创建: $BUCKET"
fi

FAILED=0
for src in $SRCS; do
  echo "================ 源环境 $src ================"
  MAIN_DUMP=$(ls -t "$DUMP_ROOT/$src"/${src}_main_*.dump 2>/dev/null | head -1 || true)
  OCR_DUMP=$(ls -t "$DUMP_ROOT/$src"/${src}_ocr_*.dump 2>/dev/null | head -1 || true)
  [ -n "$MAIN_DUMP" ] && [ -n "$OCR_DUMP" ] || {
    echo "[$src] ❌ 找不到 dump（先跑 docs/老aws账号/拉取三环境.sh $src db）"; FAILED=1; continue; }

  # 日期后缀：优先用参数，否则从文件名 <src>_main_YYYYMMDD_HHMMSS.dump 里取
  DS="$DATE_SUFFIX"
  [ -n "$DS" ] || DS=$(basename "$MAIN_DUMP" | sed -nE 's/.*_([0-9]{8})_[0-9]{6}\.dump/\1/p')
  [ -n "$DS" ] || { echo "[$src] ❌ 无法从文件名解析日期，请显式传第二个参数"; FAILED=1; continue; }
  DB_MAIN="backup_${DS}_old_${src}_main"
  DB_OCR="backup_${DS}_old_${src}_ocr"
  echo "[$src] $(basename "$MAIN_DUMP") → \"$DB_MAIN\""
  echo "[$src] $(basename "$OCR_DUMP")  → \"$DB_OCR\""

  # ⚠️ 用 stdin 而不是把路径当参数传：dump 在「备份/数据库/」下，含中文。
  # aws.exe 是 Windows 原生程序，git-bash 把含中文的路径参数交给它时会按 ANSI 编码破坏
  # （实测变成 /c/github-code/chain-serve//ݿ/dev/...，报 path does not exist）。
  # 重定向由 bash 自己打开文件，完全不经过 Windows 参数传递，中文路径照样能读。
  aws --region "$REGION" s3 cp - "s3://$BUCKET/oldbak/$src/main.dump" --only-show-errors < "$MAIN_DUMP"
  aws --region "$REGION" s3 cp - "s3://$BUCKET/oldbak/$src/ocr.dump"  --only-show-errors < "$OCR_DUMP"

  # heredoc 三个已踩过的坑（勿改）：
  #   ① 远程 set -e 下捕获退出码必须写 cmd || RC=$?，写成 cmd; RC=$? 会被 set -e 当场打死；
  #   ② 本 heredoc 未加引号 → 里面（含注释）禁止出现反引号，会在本地就被当命令执行；
  #   ③ 双引号直接写 "，不要写 \" —— 反斜杠会原样传到远端，把比较操作数变成带引号的字面量。
  REMOTE=$(cat <<EOF
set -uo pipefail
command -v pg_restore >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1 || { echo '[FATAL] 装不上 postgresql16 客户端'; exit 1; }
$PGENV
P() { psql -h $ENDPOINT -U postgres -v ON_ERROR_STOP=1 "\$@"; }
cd /tmp
aws s3 cp s3://$BUCKET/oldbak/$src/main.dump . --only-show-errors
aws s3 cp s3://$BUCKET/oldbak/$src/ocr.dump  . --only-show-errors

# 已存在则跳过：备份库是留档快照，脚本绝不替人删数据
SKIP_MAIN=0; SKIP_OCR=0
P -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_MAIN'" | grep -q 1 && SKIP_MAIN=1
P -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_OCR'"  | grep -q 1 && SKIP_OCR=1
[ \$SKIP_MAIN -eq 1 ] && echo "[跳过] $DB_MAIN 已存在（要重建请先手工 DROP DATABASE）" || P -d postgres -c 'CREATE DATABASE "$DB_MAIN";'
[ \$SKIP_OCR  -eq 1 ] && echo "[跳过] $DB_OCR 已存在" || P -d postgres -c 'CREATE DATABASE "$DB_OCR";'

RC_MAIN=0; RC_OCR=0
if [ \$SKIP_MAIN -eq 0 ]; then
  pg_restore --no-owner --no-privileges -h $ENDPOINT -U postgres -d '$DB_MAIN' main.dump || RC_MAIN=\$?
fi
if [ \$SKIP_OCR -eq 0 ]; then
  P -d '$DB_OCR' -c 'CREATE EXTENSION IF NOT EXISTS vector;' || true
  pg_restore --no-owner --no-privileges -h $ENDPOINT -U postgres -d '$DB_OCR' ocr.dump || RC_OCR=\$?
fi
echo "--- pg_restore 退出码: main=\$RC_MAIN ocr=\$RC_OCR（0=完全成功，1=有 warning，>1=硬失败）---"

echo '--- 校验 ---'
TBL=\$(P -d '$DB_MAIN' -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public'" | tr -d '[:space:]')
OTBL=\$(P -d '$DB_OCR' -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public'" | tr -d '[:space:]')
SZ=\$(P -d postgres -tAc "SELECT pg_size_pretty(pg_database_size('$DB_MAIN'))")
echo "$DB_MAIN: 表 \$TBL 个, 大小 \$SZ"
echo "$DB_OCR: 表 \$OTBL 个"
P -d '$DB_MAIN' -tAc "SELECT 'alembic 版本: '||version_num FROM alembic_version" 2>/dev/null || echo 'alembic_version 表不存在'
P -d '$DB_MAIN' -tAc "SELECT 'users 行数: '||count(*) FROM users" 2>/dev/null || true
rm -f /tmp/main.dump /tmp/ocr.dump
[ "\${TBL:-0}" -gt 0 ] || { echo '[FATAL] main 备份库表数为 0——恢复失败'; exit 1; }
[ \$RC_MAIN -le 1 ] && [ \$RC_OCR -le 1 ] || { echo '[FATAL] pg_restore 硬失败'; exit 1; }
EOF
)
  run_on_gw "$REMOTE" "restore old-$src backup dbs" || { echo "[$src] ❌ 恢复失败"; FAILED=1; }
  aws --region "$REGION" s3 rm "s3://$BUCKET/oldbak/$src/" --recursive --only-show-errors
  echo
done

[ $FAILED -eq 0 ] || { echo "===== 有环境恢复失败，见上方输出 ====="; exit 1; }
cat <<'TIP'
===== 全部恢复成功 =====
这些 css-old-*-备份_* 库是【留档快照】：不接任何应用、不在 backend.env 里引用，仅供查数据/比对 schema。
⚠️ 内含老环境的**真实 PII**（未脱敏）。若要长期留存，考虑用 05-数据库运维/mask-residual-pii.sh 处理，
   或用完即 DROP：psql -c 'DROP DATABASE "css-old-<env>-main-备份_<日期>";'
查看现有库：./restore-old-env-backup.sh --list
TIP
