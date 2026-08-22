#!/usr/bin/env bash
# 在【堡垒机】上执行 reown-db-objects.sh（每次 restore-dump-via-gw.sh / sync-db.sh 之后必跑）。
# 为什么要包装：reown-db-objects.sh 需要 <rds主机> <master密码> 参数，而 master 密码托管在
# Secrets Manager（rds! 前缀）——本脚本把 reown-db-objects.sh base64 传到堡垒机，
# 密码由堡垒机自取（角色有 GetSecretValue），**密码不进本机命令行、不进 SSM 命令文本**。
# 堡垒机定位与 SSM 执行模式照抄 restore-dump-via-gw.sh（标签对 Environment=css-shared + EnvironmentGroup=<组>）。
# 用法: ./reown-via-gw.sh <test|uat|support-ref|support-demo|support-sync|prod>
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"
cd "$(dirname "$0")"

ENV_NAME="${1:?用法: reown-via-gw.sh <test|uat|support-ref|support-demo|support-sync|prod>}"
REGION="us-east-1"
case "$ENV_NAME" in
  test|uat|support-ref|support-demo|support-sync) GW_GROUP=css-non-prod; RDS_ID=css-non-prod ;;
  prod)                               GW_GROUP=css-prod;     RDS_ID=css-prod ;;
  *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;;
esac

awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
[ "$ENDPOINT" != "None" ] || { echo "RDS $RDS_ID 不存在"; exit 1; }
echo "目标 RDS: $RDS_ID ($ENDPOINT)  环境: $ENV_NAME（owner 移交给 css_app_${ENV_NAME//-/_}）"

GW_ID=$(awsq ec2 describe-instances --filters "Name=tag:Environment,Values=css-shared" "Name=tag:EnvironmentGroup,Values=$GW_GROUP" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' | awk '{print $1}')
[ -n "$GW_ID" ] && [ "$GW_ID" != "None" ] || { echo "[FATAL] 找不到 $GW_GROUP 组运行中的堡垒机"; exit 1; }
ONLINE=$(awsq ssm describe-instance-information --filters "Key=InstanceIds,Values=$GW_ID" --query 'InstanceInformationList[0].PingStatus' 2>/dev/null || echo "")
[ "$ONLINE" = "Online" ] || { echo "堡垒机 $GW_ID 未上线 SSM"; exit 1; }

# Windows 工作区文件可能是 CRLF——先剥 CR 再编码，否则远端 bash 报 "set: pipefail: invalid option name"
B64=$(tr -d '\r' < reown-db-objects.sh | base64 -w0)

REMOTE=$(cat <<EOF
set -euo pipefail
export PGPASSWORD_PASS=\$(aws secretsmanager get-secret-value --region $REGION --secret-id '$SECRET_ARN' --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
echo '$B64' | base64 -d > /tmp/reown-db-objects.sh
bash /tmp/reown-db-objects.sh '$ENDPOINT' "\$PGPASSWORD_PASS" '$ENV_NAME'
RC=\$?
rm -f /tmp/reown-db-objects.sh
exit \$RC
EOF
)

PARAMS=$( (python3 - "$REMOTE" 2>/dev/null || python - "$REMOTE") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["1200"]}))
PY
)

echo "在堡垒机 $GW_ID 上执行 reown…"
CID=$(awsq ssm send-command --instance-ids "$GW_ID" --document-name AWS-RunShellScript \
  --comment "reown css-$ENV_NAME" --parameters "$PARAMS" --query 'Command.CommandId')
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$GW_ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 10
done
echo "状态: $ST"
awsq ssm get-command-invocation --command-id "$CID" --instance-id "$GW_ID" --query StandardOutputContent 2>/dev/null || true
if [ "$ST" != "Success" ]; then
  awsq ssm get-command-invocation --command-id "$CID" --instance-id "$GW_ID" --query StandardErrorContent 2>/dev/null | tail -20
  echo "[FATAL] reown 失败（状态 $ST）——不移交 owner，应用账号跑 alembic 会报 must be owner"
  exit 1
fi
echo "===== reown 完成：css-$ENV_NAME-main / css-$ENV_NAME-ocr 对象 owner 已移交 css_app_${ENV_NAME//-/_} ====="
