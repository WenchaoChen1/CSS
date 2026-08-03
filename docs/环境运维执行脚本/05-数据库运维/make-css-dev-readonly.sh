#!/usr/bin/env bash
# 把 css_dev 角色降为【非生产实例上所有库的只读】（2026-08-03 拍板）：
#   - 撤销 CREATEDB / CREATEROLE（不能再建库）；
#   - 对实例上每一个库（含 backup_* 留档库，排除 rdsadmin）：只留 CONNECT + USAGE + SELECT，
#     撤销全部写权限（INSERT/UPDATE/DELETE/TRUNCATE/…）与 public schema 的 CREATE；
#   - 同步改写默认权限（ALTER DEFAULT PRIVILEGES），今后 postgres / css_app_* 新建的表自动只给 SELECT。
# 与 create-db-accounts.sh 的关系：那边负责【建账号+首次授权】（其 css_dev 段已同步改为只读口径）；
#   本脚本负责【把存量权限收敛到只读】，且**新建/恢复一个库之后要重跑一次**（默认权限不跨库）。
# 执行链路：本机 → SSM → 网关机 psql16（master 密码由网关机自取 Secrets Manager，不进命令文本）。
# 用法: ./make-css-dev-readonly.sh          # 收敛 + 验证
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

REGION="us-east-1"; RDS_ID="css-non-prod"; GW_GROUP="css-non-prod"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
GW_ID=$(awsq ec2 describe-instances \
  --filters "Name=tag:Environment,Values=css-shared" "Name=tag:EnvironmentGroup,Values=$GW_GROUP" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' | awk '{print $1}')
[ -n "$GW_ID" ] && [ "$GW_ID" != "None" ] || { echo "[FATAL] 找不到网关机"; exit 1; }

REMOTE_B64=$( { cat <<'EOS'
set -uo pipefail
command -v psql >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1 || { echo '[FATAL] 装不上 psql16'; exit 1; }
export PGPASSWORD=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id "$SECRET_ARN" --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
P() { psql -h "$ENDPOINT" -U postgres -v ON_ERROR_STOP=1 "$@"; }

P -d postgres -c 'ALTER ROLE css_dev NOCREATEDB NOCREATEROLE;'
DBS=$(P -d postgres -tAc "select datname from pg_database where not datistemplate and datname <> 'rdsadmin' order by 1")
FAIL=0
for db in $DBS; do
  P -d postgres -c "GRANT CONNECT ON DATABASE \"$db\" TO css_dev;" >/dev/null
  P -d "$db" >/dev/null <<'SQL'
REVOKE CREATE ON SCHEMA public FROM css_dev;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM css_dev;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM css_dev;
GRANT USAGE ON SCHEMA public TO css_dev;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO css_dev;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO css_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM css_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM css_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO css_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO css_dev;
SQL
  # 表 owner 可能已移交给 css_app_*（reown-db-objects.sh）——它们未来建的表也只给 SELECT
  for r in css_app_test css_app_uat; do
    P -d "$db" -c "ALTER DEFAULT PRIVILEGES FOR ROLE $r IN SCHEMA public REVOKE ALL ON TABLES FROM css_dev;" >/dev/null 2>&1 || true
    P -d "$db" -c "ALTER DEFAULT PRIVILEGES FOR ROLE $r IN SCHEMA public GRANT SELECT ON TABLES TO css_dev;" >/dev/null 2>&1 || true
  done
done

echo '--- 验证（每库：可INSERT 必须为 0）---'
echo "css_dev CREATEDB=$(P -d postgres -tAc "select rolcreatedb from pg_roles where rolname='css_dev'")（应为 f）"
for db in $DBS; do
  T=$(P -d "$db" -tAc "select count(*) from information_schema.tables where table_schema='public'")
  S=$(P -d "$db" -tAc "select count(*) from information_schema.tables where table_schema='public' and has_table_privilege('css_dev', quote_ident(table_schema)||'.'||quote_ident(table_name), 'SELECT')")
  W=$(P -d "$db" -tAc "select count(*) from information_schema.tables where table_schema='public' and has_table_privilege('css_dev', quote_ident(table_schema)||'.'||quote_ident(table_name), 'INSERT')")
  echo "$db: 表 $T | 可SELECT $S | 可INSERT $W"
  [ "$W" = "0" ] || FAIL=1
  [ "$S" = "$T" ] || FAIL=1
done
[ "$FAIL" = "0" ] || { echo '[FATAL] 有库未收敛到只读，见上'; exit 1; }
echo '✅ css_dev 已是全实例只读'
EOS
} | base64 -w0 )

PARAMS=$(EP="$ENDPOINT" SEC="$SECRET_ARN" B64="$REMOTE_B64" python - <<'PY'
import json, os
cmd = ("echo %s | base64 -d > /tmp/devro.sh && ENDPOINT=%s SECRET_ARN=%s bash /tmp/devro.sh; RC=$?; rm -f /tmp/devro.sh; exit $RC"
      ) % (os.environ['B64'], os.environ['EP'], os.environ['SEC'])
print(json.dumps({"commands":[cmd],"executionTimeout":["900"]}))
PY
)
CMD_ID=$(awsq ssm send-command --instance-ids "$GW_ID" --document-name AWS-RunShellScript \
  --comment "make css_dev readonly" --parameters "$PARAMS" --query 'Command.CommandId')
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 8
done
aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" \
  --query 'StandardOutputContent' --output text | tr -d '\r'
[ "$ST" = "Success" ] || { echo "[FATAL] 执行失败（SSM $ST）："; aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query 'StandardErrorContent' --output text | tr -d '\r'; exit 1; }
