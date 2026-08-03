#!/usr/bin/env bash
# 重命名非生产 RDS 上的一个数据库（本机执行，经 SSM 由网关机操作，RDS 在私有子网连不到）。
# 用法: ./rename-db.sh <旧库名> <新库名>
#   新库名强制英文规范：^[a-z][a-z0-9_]*$（小写字母/数字/下划线，无需引号、无编码歧义）——
#   2026-08-03 规范：库名一律英文；备份库前缀 backup_ 放最前（backup_<YYYYMMDD>_...）。
# 安全性：目标库有活动连接时 PG 自己会拒绝 RENAME；新名已存在则脚本拒绝执行。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

OLD="${1:?用法: rename-db.sh <旧库名> <新库名> [--kick]}"
NEW="${2:?缺新库名}"
KICK="${3:-}"   # --kick = 改名前先 pg_terminate_backend 断掉该库全部连接（仅对无应用使用的库用，如 backup_* 留档库）
REGION="us-east-1"; RDS_ID="css-non-prod"; GW_GROUP="css-non-prod"

echo "$NEW" | grep -qE '^[a-z][a-z0-9_]*$' || { echo "[FATAL] 新库名必须匹配 ^[a-z][a-z0-9_]*$（纯英文小写+数字+下划线）: $NEW"; exit 1; }

awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
GW_ID=$(awsq ec2 describe-instances \
  --filters "Name=tag:Environment,Values=css-shared" "Name=tag:EnvironmentGroup,Values=$GW_GROUP" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' | awk '{print $1}')
[ -n "$GW_ID" ] && [ "$GW_ID" != "None" ] || { echo "[FATAL] 找不到网关机"; exit 1; }

# 远程脚本走 base64（旧库名可能含中文/特殊字符，base64 后全程 ASCII，零转义风险）；
# 密码由网关机自己从 Secrets Manager 取，不进命令文本。
REMOTE_B64=$( { cat <<'EOS'
set -uo pipefail
command -v psql >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1 || { echo '[FATAL] 装不上 psql16'; exit 1; }
export PGPASSWORD=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id "$SECRET_ARN" --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
P() { psql -h "$ENDPOINT" -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
[ "$(P -tAc "SELECT count(*) FROM pg_database WHERE datname='$OLDDB'")" = "1" ] || { echo "[FATAL] 旧库不存在: $OLDDB"; exit 1; }
[ "$(P -tAc "SELECT count(*) FROM pg_database WHERE datname='$NEWDB'")" = "0" ] || { echo "[FATAL] 新库名已存在: $NEWDB"; exit 1; }
if [ "${KICK:-}" = "--kick" ]; then
  N=$(P -tAc "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE datname='$OLDDB' AND pid<>pg_backend_pid()")
  echo "已断开 $OLDDB 上的 $N 个连接"
fi
# ⚠️ 本远程段没有 set -e（沿用 set -uo）——失败必须显式退出，否则会假报 OK（2026-08-03 实踩：
#   dev_main 因残留活动连接 RENAME 失败，却照样打印了 OK）
P -c "ALTER DATABASE \"$OLDDB\" RENAME TO \"$NEWDB\";" || {
  echo "[FATAL] RENAME 失败（最常见原因：库上有活动连接，见下）"
  P -tAc "SELECT '占用连接: pid='||pid||' app='||coalesce(application_name,'?')||' 状态='||state FROM pg_stat_activity WHERE datname='$OLDDB'"
  exit 1
}
[ "$(P -tAc "SELECT count(*) FROM pg_database WHERE datname='$NEWDB'")" = "1" ] || { echo '[FATAL] 改名后新库不存在——异常'; exit 1; }
echo "OK 已改名 → $NEWDB ($(P -tAc "SELECT pg_size_pretty(pg_database_size('$NEWDB'))"))"
EOS
} | base64 -w0 )

PARAMS=$(OLD="$OLD" NEW="$NEW" KICK="$KICK" EP="$ENDPOINT" SEC="$SECRET_ARN" B64="$REMOTE_B64" python - <<'PY'
import json, os, base64
# 旧库名可能含中文：不能走 json.dumps 直接内嵌（默认转成 \uXXXX 字面量，shell 不解释），
# 统一 base64 编码、远端 base64 -d 还原——命令文本全程 ASCII，零编码歧义。
old_b64 = base64.b64encode(os.environ['OLD'].encode('utf-8')).decode()
cmd = ("echo %s | base64 -d > /tmp/rename-db.sh && "
       "OLDDB=\"$(echo %s | base64 -d)\" NEWDB=%s KICK=%s ENDPOINT=%s SECRET_ARN=%s bash /tmp/rename-db.sh; RC=$?; rm -f /tmp/rename-db.sh; exit $RC"
      ) % (os.environ['B64'], old_b64, os.environ['NEW'], os.environ.get('KICK') or "''", os.environ['EP'], os.environ['SEC'])
print(json.dumps({"commands":[cmd],"executionTimeout":["300"]}))
PY
)
CMD_ID=$(awsq ssm send-command --instance-ids "$GW_ID" --document-name AWS-RunShellScript \
  --comment "rename db" --parameters "$PARAMS" --query 'Command.CommandId')
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 5
done
aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" \
  --query 'StandardOutputContent' --output text | tr -d '\r'
[ "$ST" = "Success" ] || { echo "[FATAL] 改名失败（SSM $ST）："; aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query 'StandardErrorContent' --output text | tr -d '\r'; exit 1; }
