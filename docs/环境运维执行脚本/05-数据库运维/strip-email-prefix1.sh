#!/usr/bin/env bash
# 修复脱敏误伤：把被 anonymize-db.sh 误加前缀 "1" 的团队邮箱去掉前缀（1spwfoo@bar → spwfoo@bar）。
# 背景：2026-08-22 test/uat 脱敏用 --skip-email-prefix swp 只放行了 swp* 开头的邮箱，
#       拼写为 spw* 的团队邮箱没被排除、被误加了 1，导致收不到信。
# 行为：动态遍历 information_schema 里所有 email 类文本列（与 anonymize-db.sh 同一口径），
#       对值形如 1<前缀>% 的行执行 SET col = substring(col from 2)；先打印命中明细再单事务更新，
#       完成后写 _css_pii_masked 标记一条修复记录。幂等：重跑命中 0 行。
# 用法: ./strip-email-prefix1.sh <test|uat|support-ref|support-demo|support-sync> <前缀1>[,前缀2...]
#   例: ./strip-email-prefix1.sh uat swp,spw
# 不支持 prod（prod 未做 swp 排除脱敏，不存在本误伤场景）。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: strip-email-prefix1.sh <test|uat|support-ref|support-demo|support-sync> <前缀1>[,前缀2...]}"
PREFIX_CSV="${2:?需要至少一个邮箱前缀，逗号分隔，如 swp,spw}"
REGION="us-east-1"
case "$ENV_NAME" in
  test|uat|support-ref|support-demo|support-sync) ;;
  *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync（不支持 prod）"; exit 1 ;;
esac

# 前缀会拼进 SQL 字面量，只放行安全字符，防注入（与 anonymize-db.sh 同规则）
COND=""; EXTRA_ARGS=""
IFS=',' read -ra PREFIXES <<< "$PREFIX_CSV"
for P in "${PREFIXES[@]}"; do
  [ -n "$P" ] || continue
  case "$P" in
    *[!A-Za-z0-9_.@+-]*) echo "前缀只允许字母数字与 _ . @ + -：$P"; exit 1 ;;
  esac
  COND="${COND:+$COND OR }%I ILIKE ''1${P}%%''"
  EXTRA_ARGS="$EXTRA_ARGS, column_name"
done
[ -n "$COND" ] || { echo "前缀列表为空"; exit 1; }

FIX_NOTE="strip-email-prefix1.sh: 去掉 1+(${PREFIX_CSV//,/|}) 开头邮箱的误加前缀 1"

REMOTE=$(cat <<REOF
set -euo pipefail
EF=/opt/css-cicd/env/$ENV_NAME/backend.env
gv() { { grep -E "^\$1=" "\$EF" || true; } | tail -1 | cut -d= -f2- | tr -d '"\r'; }
export PGPASSWORD="\$(gv POSTGRES_PASSWORD)"
HOSTDB="\$(gv POSTGRES_HOST)"; USERDB="\$(gv POSTGRES_USER)"; DBNAME="\$(gv POSTGRES_DB)"
PSQL="docker run --rm -i -e PGPASSWORD=\$PGPASSWORD postgres:16 psql -h \$HOSTDB -U \$USERDB -d \$DBNAME -v ON_ERROR_STOP=1"

# 与 anonymize-db.sh 同一列口径：public 下文本类 email 列，排除枚举类 *type* 列
COLSQL="FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%email%' AND column_name NOT ILIKE '%type%'"

echo "--- 命中明细（修复前）---"
\$PSQL -tAc "
SELECT format('SELECT ''%s.%s: ''||%I FROM %I.%I WHERE $COND;',
              table_name, column_name, column_name, table_schema, table_name$EXTRA_ARGS)
\$COLSQL" > /tmp/strip_preview.sql
\$PSQL -tA < /tmp/strip_preview.sql
HIT=\$(\$PSQL -tA < /tmp/strip_preview.sql | wc -l)
rm -f /tmp/strip_preview.sql
echo "--- 共命中 \$HIT 行 ---"
if [ "\$HIT" -eq 0 ]; then echo "无需修复，退出"; exit 0; fi

# 生成 UPDATE 并单事务执行 + 写修复标记（note 文本不能含 ASCII 单引号）
\$PSQL -tAc "
SELECT format('UPDATE %I.%I SET %I = substring(%I from 2) WHERE $COND;',
              table_schema, table_name, column_name, column_name$EXTRA_ARGS)
\$COLSQL" > /tmp/strip_fix.sql
cat /tmp/strip_fix.sql
{ echo 'BEGIN;'; cat /tmp/strip_fix.sql
  echo "CREATE TABLE IF NOT EXISTS _css_pii_masked (id serial PRIMARY KEY, masked_at timestamptz NOT NULL DEFAULT now(), masked_by text NOT NULL, mode text NOT NULL, note text);"
  echo "INSERT INTO _css_pii_masked(masked_by, mode, note) VALUES ('strip-email-prefix1.sh', 'strip-prefix1-fix', '$FIX_NOTE');"
  echo 'COMMIT;'; } | \$PSQL
rm -f /tmp/strip_fix.sql

echo "--- 修复后校验（应为 0 行残留）---"
\$PSQL -tAc "
SELECT format('SELECT ''%s.%s 残留: ''||count(*) FROM %I.%I WHERE $COND;',
              table_name, column_name, table_schema, table_name$EXTRA_ARGS)
\$COLSQL" > /tmp/strip_chk.sql
\$PSQL -tA < /tmp/strip_chk.sql
BAD=\$(\$PSQL -tA < /tmp/strip_chk.sql | awk -F': ' '{if (\$2+0 > 0) c++} END{print c+0}')
rm -f /tmp/strip_chk.sql
[ "\$BAD" -eq 0 ] || { echo "[FATAL] 仍有 \$BAD 个列存在残留，修复未彻底"; exit 1; }
REOF
)

PARAMS=$( (python3 - "$REMOTE" 2>/dev/null || python - "$REMOTE") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["900"]}))
PY
)
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
ID=$(awsq ec2 describe-instances --filters "Name=tag:Environment,Values=css-$ENV_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId')
if [ "$ID" != "None" ] && [ -n "$ID" ]; then
  ONLINE=$(awsq ssm describe-instance-information --filters "Key=InstanceIds,Values=$ID" --query 'InstanceInformationList[0].PingStatus')
  [ "$ONLINE" = "Online" ] || { echo "$ENV_NAME 应用机 $ID 未注册 SSM"; exit 1; }
fi
[ "$ID" != "None" ] && [ -n "$ID" ] || { echo "找不到在线的 $ENV_NAME 应用机"; exit 1; }
echo "在 $ID 上执行…"
CID=$(awsq ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
  --comment "strip-email-prefix1 css-$ENV_NAME" --parameters "$PARAMS" --query 'Command.CommandId')
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 10
done
echo "状态: $ST"
awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardOutputContent 2>/dev/null || true

if [ "$ST" != "Success" ]; then
  awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardErrorContent 2>/dev/null | tail -20
  echo ""
  echo "[FATAL] 修复失败（状态 $ST），事务已回滚，库内数据未变更"
  exit 1
fi
echo ""
echo "===== 修复完成：1+(${PREFIX_CSV//,/|}) 开头的邮箱已去掉误加的前缀 1 ====="
