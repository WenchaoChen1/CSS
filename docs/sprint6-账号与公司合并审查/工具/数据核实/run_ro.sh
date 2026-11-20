#!/usr/bin/env bash
# 只读查库：本机取 RDS 地址和 master secret ARN，经堡垒机现取密码（不落盘、不出 AWS），只读会话执行 SQL 文件。
# 用法：run_ro.sh <test|uat|prod> <sql 文件> [库名，默认 css-<env>-main]
set -euo pipefail
ENV="$1"; SQL_FILE="$2"; DB="${3:-css-$1-main}"
WS=/c/github-code/css
case "$ENV" in
  test|uat) BASTION=3.225.148.166; KEY="$WS/deploy-env/ssh/css-non-prod-gw.pem"; RDS_ID=css-non-prod ;;
  prod)     BASTION=34.225.237.45; KEY="$WS/deploy-env/ssh/css-prod-bastion";   RDS_ID=css-prod ;;
  *) echo "env?"; exit 2 ;;
esac
INFO=$(PYTHONUTF8=1 python -c "import boto3;d=boto3.client('rds','us-east-1').describe_db_instances(DBInstanceIdentifier='$RDS_ID')['DBInstances'][0];print(d['Endpoint']['Address']+' '+d['MasterUserSecret']['SecretArn'])")
INFO="${INFO//$'\r'/}"
EP="${INFO%% *}"; ARN="${INFO#* }"
B64=$(base64 -w0 "$SQL_FILE")
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -i "$KEY" ec2-user@"$BASTION" bash -s <<REMOTE
set -euo pipefail
F=\$(mktemp /tmp/ro_XXXX.sql); echo '$B64' | base64 -d > "\$F"
SECRET=\$(aws secretsmanager get-secret-value --region us-east-1 --secret-id '$ARN' --query SecretString --output text)
export PGUSER=\$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["username"])' "\$SECRET")
export PGPASSWORD=\$(python3 -c 'import json,sys;print(json.loads(sys.argv[1])["password"])' "\$SECRET")
export PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=120000 -c lock_timeout=3000'
psql -h $EP -d '$DB' -v ON_ERROR_STOP=0 -X -q -P pager=off -f "\$F"
rm -f "\$F"
REMOTE
