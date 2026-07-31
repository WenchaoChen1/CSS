#!/usr/bin/env bash
# 把本地 pg_dump -Fc 备份恢复到私有子网里的 RDS（本地无法直连时用）：
#   本地 dump → S3 中转桶 css-dbsync-<账号> → SSM Run Command 在网关机上执行
#   （装 psql 客户端 → 从 Secrets Manager 取 RDS 托管密码 → 建库/pgvector → pg_restore → 清理）。
# 前置：网关机已由 06-服务器密钥与访问/create-gateway.sh 挂 css-gw-<组> profile（SSM + 读桶 + 读 rds! 密码）。
# 目标库名按 2026-07-28 规范：css-<env>-main / css-<env>-ocr（ocr 自动加 pgvector）。
# 用法: ./restore-dump-via-gw.sh <test|uat|prod> <main库dump> <ocr库dump>
#   例: ./restore-dump-via-gw.sh test ../../../备份/数据库/preprod/preprod_main_xxx.dump ../../../备份/数据库/preprod/preprod_ocr_xxx.dump
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"  # git-bash: 防参数被误转 Windows 路径

ENV_NAME="${1:?用法: restore-dump-via-gw.sh <test|uat|prod> <main.dump> <ocr.dump>}"
MAIN_DUMP="${2:?缺 main 库 dump 文件}"
OCR_DUMP="${3:?缺 ocr 库 dump 文件}"
REGION="us-east-1"
[ -f "$MAIN_DUMP" ] || { echo "文件不存在: $MAIN_DUMP"; exit 1; }
[ -f "$OCR_DUMP" ]  || { echo "文件不存在: $OCR_DUMP"; exit 1; }

case "$ENV_NAME" in
  test|uat) GW_NAME=css-non-prod-gw;   RDS_ID=css-non-prod ;;
  prod)     GW_NAME=css-prod-bastion; RDS_ID=css-prod ;;
  *) echo "环境必须是 test|uat|prod"; exit 1 ;;
esac
if [ "$ENV_NAME" = "prod" ]; then
  read -r -p "[WARN] 即将【覆盖恢复生产库】css-prod-main/css-prod-ocr，输入 prod 确认: " ok
  [ "$ok" = "prod" ] || { echo "已取消"; exit 1; }
fi

awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
ACCOUNT_ID=$(awsq sts get-caller-identity --query Account)
BUCKET="css-dbsync-$ACCOUNT_ID"

# ---- RDS 端点 + 托管密码 secret（密码不出 AWS：网关机上自取）----
ENDPOINT=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].Endpoint.Address')
SECRET_ARN=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].MasterUserSecret.SecretArn')
[ "$ENDPOINT" != "None" ] || { echo "RDS $RDS_ID 不存在"; exit 1; }
echo "目标 RDS: $RDS_ID ($ENDPOINT)  库: css-$ENV_NAME-main / css-$ENV_NAME-ocr"

# ---- 网关机（SSM 目标）----
GW_ID=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=$GW_NAME" "Name=instance-state-name,Values=running" --query 'Reservations[0].Instances[0].InstanceId')
[ "$GW_ID" != "None" ] || { echo "网关机 $GW_NAME 未运行（先跑 06-服务器密钥与访问/create-gateway.sh）"; exit 1; }
echo -n "等待网关机注册到 SSM"
for i in $(seq 1 30); do
  ONLINE=$(awsq ssm describe-instance-information --filters "Key=InstanceIds,Values=$GW_ID" --query 'InstanceInformationList[0].PingStatus' 2>/dev/null || echo "")
  [ "$ONLINE" = "Online" ] && break; echo -n "."; sleep 10
done; echo " $ONLINE"
[ "$ONLINE" = "Online" ] || { echo "网关机未上线 SSM（检查 profile/出网）"; exit 1; }

# ---- S3 中转桶（私有 + 默认加密，dump 用完即删）----
if ! aws --region "$REGION" s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws --region "$REGION" s3api create-bucket --bucket "$BUCKET" >/dev/null
  aws --region "$REGION" s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws --region "$REGION" s3api put-bucket-tagging --bucket "$BUCKET" --tagging 'TagSet=[{Key=Group,Value=css-ops}]'
  echo "中转桶创建: $BUCKET"
fi
aws --region "$REGION" s3 cp "$MAIN_DUMP" "s3://$BUCKET/$ENV_NAME/main.dump" --only-show-errors
aws --region "$REGION" s3 cp "$OCR_DUMP"  "s3://$BUCKET/$ENV_NAME/ocr.dump"  --only-show-errors
echo "dump 已上传 s3://$BUCKET/$ENV_NAME/"

# ---- 网关机上执行恢复（命令经 python json 编码，避免引号/换行踩坑）----
REMOTE=$(cat <<EOF
set -euo pipefail
command -v pg_restore >/dev/null || dnf install -y postgresql16 >/dev/null 2>&1 || dnf install -y postgresql15 >/dev/null
export PGPASSWORD=\$(aws secretsmanager get-secret-value --region $REGION --secret-id '$SECRET_ARN' --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
P() { psql -h $ENDPOINT -U postgres -v ON_ERROR_STOP=1 "\$@"; }
cd /tmp && aws s3 cp s3://$BUCKET/$ENV_NAME/main.dump . --only-show-errors && aws s3 cp s3://$BUCKET/$ENV_NAME/ocr.dump . --only-show-errors
for db in css-$ENV_NAME-main css-$ENV_NAME-ocr; do
  P -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='\$db'" | grep -q 1 || P -d postgres -c "CREATE DATABASE \"\$db\";"
done
P -d 'css-$ENV_NAME-ocr' -c 'CREATE EXTENSION IF NOT EXISTS vector;'
pg_restore --no-owner --no-privileges --clean --if-exists -h $ENDPOINT -U postgres -d 'css-$ENV_NAME-main' main.dump || true
pg_restore --no-owner --no-privileges --clean --if-exists -h $ENDPOINT -U postgres -d 'css-$ENV_NAME-ocr'  ocr.dump  || true
echo '--- 校验 ---'
P -d 'css-$ENV_NAME-main' -tAc "SELECT 'main 表数: '||count(*) FROM pg_tables WHERE schemaname='public'"
P -d 'css-$ENV_NAME-main' -tAc "SELECT 'alembic: '||version_num FROM alembic_version" || true
P -d 'css-$ENV_NAME-ocr'  -tAc "SELECT 'ocr 表数: '||count(*) FROM pg_tables WHERE schemaname='public'"
rm -f /tmp/main.dump /tmp/ocr.dump
EOF
)
PARAMS=$( (python3 - "$REMOTE" 2>/dev/null || python - "$REMOTE") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["1800"]}))
PY
)
CMD_ID=$(awsq ssm send-command --instance-ids "$GW_ID" \
  --document-name AWS-RunShellScript --comment "restore css-$ENV_NAME dbs" \
  --parameters "$PARAMS" --query 'Command.CommandId')
echo "SSM 命令: $CMD_ID（恢复中…）"
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 10
done
aws --region "$REGION" ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$GW_ID" \
  --query '{status:Status,out:StandardOutputContent,err:StandardErrorContent}' --output json | tr -d '\r'

# ---- 清理中转对象 ----
aws --region "$REGION" s3 rm "s3://$BUCKET/$ENV_NAME/" --recursive --only-show-errors
echo "===== 恢复流程结束（状态见上方 status；pg_restore 的 warning 属正常）====="
echo "提醒: /css/$ENV_NAME/backend.env 里 POSTGRES_DB=css-$ENV_NAME-main、OCR 两个 URL 指向 css-$ENV_NAME-ocr，改完重跑 11-parameter-store/put-params.sh"
