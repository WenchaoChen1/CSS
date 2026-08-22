#!/usr/bin/env bash
# 在 template1 里预置 css_dev 的只读授权（2026-08-22 用户拍板，"B 兜底"方案）：
#   此后任何 CREATE DATABASE（默认模板=template1）克隆出的新库【天生】带有——
#   ① public schema 的 USAGE；② postgres / css_app_* 名下的默认权限（新建表/序列自动给 css_dev SELECT）。
#   pg_restore 以 postgres 身份建表 → 恢复进"新库"的存量表也会在建表时刻自动带上 SELECT。
# 边界（写清楚，防误解）：
#   - 只影响【本脚本执行之后】新建的库；存量库不受影响（存量走 make-css-dev-readonly.sh）；
#   - CREATE DATABASE ... TEMPLATE template0 会绕过本预置（我们的脚本链都用默认模板）；
#   - 显式保障另见"A 挂钩"：restore-dump-via-gw.sh / restore-old-env-backup.sh / backup-db-in-rds.sh
#     尾部已内嵌同款授权（双保险，两者独立生效）。
# 执行链路：本机 → SSM → 堡垒机 psql16（master 密码堡垒机自取，不进命令文本）。
# 用法: ./seed-template1-readonly.sh                 # 非生产实例
#       ./seed-template1-readonly.sh --to css-prod   # 生产实例
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

REGION="us-east-1"
TARGET="css-non-prod"
[ "${1:-}" = "--to" ] && TARGET="${2:?--to 需要 css-non-prod|css-prod}"
case "$TARGET" in css-non-prod|css-prod) ;; *) echo "--to 只能是 css-non-prod|css-prod"; exit 1 ;; esac
RDS_ID="$TARGET"; GW_GROUP="$TARGET"
if [ "$TARGET" = "css-prod" ]; then
  OWNER_ROLES="css_app_prod"
else
  OWNER_ROLES="css_app_test css_app_uat css_app_support_ref css_app_support_demo css_app_support_sync"
fi

awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
GW_ID=$(awsq ec2 describe-instances \
  --filters "Name=tag:Environment,Values=css-shared" "Name=tag:EnvironmentGroup,Values=$GW_GROUP" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' | awk '{print $1}')
[ -n "$GW_ID" ] && [ "$GW_ID" != "None" ] || { echo "[FATAL] 找不到 $GW_GROUP 堡垒机"; exit 1; }
echo "目标: $RDS_ID ($ENDPOINT) template1｜owner 名单: $OWNER_ROLES"

REMOTE_B64=$( { cat <<'EOS'
set -uo pipefail
command -v psql >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1 || { echo '[FATAL] 装不上 psql16'; exit 1; }
export PGPASSWORD=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id "$SECRET_ARN" --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
P() { psql -h "$ENDPOINT" -U postgres -v ON_ERROR_STOP=1 "$@"; }

echo "--- 预置 template1 ---"
P -d template1 -c 'GRANT USAGE ON SCHEMA public TO css_dev;'
P -d template1 -c 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO css_dev;'
P -d template1 -c 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO css_dev;'
for r in $OWNER_ROLES; do
  P -d template1 -c "ALTER DEFAULT PRIVILEGES FOR ROLE $r IN SCHEMA public GRANT SELECT ON TABLES TO css_dev;" >/dev/null 2>&1 || true
  P -d template1 -c "ALTER DEFAULT PRIVILEGES FOR ROLE $r IN SCHEMA public GRANT SELECT ON SEQUENCES TO css_dev;" >/dev/null 2>&1 || true
done

echo "--- 端到端验证：克隆临时库→建表→css_dev 应自动可读 ---"
P -d postgres -c 'DROP DATABASE IF EXISTS tmp_tpl_check;' >/dev/null
P -d postgres -c 'CREATE DATABASE tmp_tpl_check;' >/dev/null
P -d tmp_tpl_check -c 'CREATE TABLE _probe(x int);' >/dev/null
OK=$(P -d tmp_tpl_check -tAc "select has_table_privilege('css_dev','public._probe','SELECT')")
P -d postgres -c 'DROP DATABASE tmp_tpl_check;' >/dev/null
echo "克隆库新表 css_dev 可SELECT: $OK（应为 t）"
[ "$OK" = "t" ] || { echo '[FATAL] 预置未生效'; exit 1; }
echo '✅ template1 预置完成：此后新建库自动携带 css_dev 只读'
EOS
} | base64 -w0 )

PARAMS=$(EP="$ENDPOINT" SEC="$SECRET_ARN" B64="$REMOTE_B64" ROLES="$OWNER_ROLES" python - <<'PY'
import json, os
cmd = ("echo %s | base64 -d > /tmp/tplro.sh && ENDPOINT=%s SECRET_ARN=%s OWNER_ROLES='%s' bash /tmp/tplro.sh; RC=$?; rm -f /tmp/tplro.sh; exit $RC"
      ) % (os.environ['B64'], os.environ['EP'], os.environ['SEC'], os.environ['ROLES'])
print(json.dumps({"commands":[cmd],"executionTimeout":["600"]}))
PY
)
CMD_ID=$(awsq ssm send-command --instance-ids "$GW_ID" --document-name AWS-RunShellScript \
  --comment "seed template1 css_dev readonly" --parameters "$PARAMS" --query 'Command.CommandId')
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 8
done
aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" \
  --query 'StandardOutputContent' --output text | tr -d '\r'
[ "$ST" = "Success" ] || { echo "[FATAL] 执行失败（SSM $ST）："; aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query 'StandardErrorContent' --output text | tr -d '\r'; exit 1; }
