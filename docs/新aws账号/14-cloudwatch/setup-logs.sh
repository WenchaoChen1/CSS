#!/usr/bin/env bash
# 容器日志 → CloudWatch Logs：建日志组 + 设保留期 + 给实例角色加写权限。
#
# 日志组划分（2026-07-29 按"要能以整个环境的方式查询"定的）：
#   **一个环境一个日志组** /css/<env>，服务用 log stream 名区分（stream 名 = 容器名，
#   如 css-test-backend-app-1、css-test-frontend-frontend-1）。
#   这样查整个环境只需选一个日志组；查单个服务加一句 filter @logStream like /backend-app/ 即可。
#   （若按服务拆成 9 个组，查"整个环境"就得一次勾 9 个组，正好和需求相反。）
#
# 保留期：test 7 天 / uat 14 天 / prod 30 天。
#   ⚠️ 日志组默认【永不过期】，不设保留期费用会一直累积——这是 CloudWatch Logs 最常见的坑。
#
# 用法: ./setup-logs.sh <test|uat|prod> [保留天数]
# 执行完还要改 compose 的 logging driver（见 README「落地步骤」），本脚本只准备云端资源与权限。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: setup-logs.sh <test|uat|prod> [保留天数]}"
case "$ENV_NAME" in
  test) DEF_RET=7;  GROUP=css-non-prod ;;
  uat)  DEF_RET=14; GROUP=css-non-prod ;;
  prod) DEF_RET=30; GROUP=css-prod ;;
  *) echo "环境必须是 test|uat|prod"; exit 1 ;;
esac
RETENTION="${2:-$DEF_RET}"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
LOG_GROUP="/css/$ENV_NAME"

echo "=== 1) 日志组 $LOG_GROUP（保留 $RETENTION 天）==="
if aws --region "$REGION" logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" \
     --query "logGroups[?logGroupName=='$LOG_GROUP'].logGroupName" --output text | tr -d '\r' | grep -q .; then
  echo "  已存在，仅刷新保留期与标签"
else
  aws --region "$REGION" logs create-log-group --log-group-name "$LOG_GROUP" \
    --tags "Group=$GROUP,CssEnv=css-$ENV_NAME"
  echo "  已创建"
fi
aws --region "$REGION" logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days "$RETENTION"
aws --region "$REGION" logs tag-log-group --log-group-name "$LOG_GROUP" \
  --tags "Group=$GROUP,CssEnv=css-$ENV_NAME" 2>/dev/null || true
echo "  保留期: $RETENTION 天；标签: Group=$GROUP CssEnv=css-$ENV_NAME"

echo "=== 2) 给实例角色 css-ec2-$ENV_NAME 加写日志权限 ==="
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMPF=$(cygpath -m "$TMP"); else TMPF="$TMP"; fi
cat > "$TMP/logs.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "WriteOwnEnvLogs", "Effect": "Allow",
      "Action": ["logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams"],
      "Resource": "arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$LOG_GROUP:*" },
    { "Sid": "DescribeGroups", "Effect": "Allow",
      "Action": "logs:DescribeLogGroups", "Resource": "*" }
  ]
}
EOF
aws iam put-role-policy --role-name "css-ec2-$ENV_NAME" \
  --policy-name "css-ec2-$ENV_NAME-logs" --policy-document "file://$TMPF/logs.json"
echo "  已挂策略 css-ec2-$ENV_NAME-logs（只能写 $LOG_GROUP，不能读别的环境）"
echo "  注意：故意不给 logs:CreateLogGroup——组由本脚本预建并设好保留期，"
echo "        让容器自动建组会建出【永不过期】的组，费用无上限。"

echo ""
echo "===== $ENV_NAME 日志侧云端资源就绪 ====="
echo "接下来改 compose 的 logging driver（deploy/compose/{infra,backend,frontend}.yml 的 x-logging）："
cat <<'YAML'
  x-logging: &logging
    driver: awslogs
    options:
      awslogs-region: us-east-1
      awslogs-group: /css/${DEPLOY_ENV:?}
      awslogs-create-group: "false"
      tag: "{{.Name}}"        # log stream 名 = 容器名，便于按服务过滤
      mode: non-blocking      # 关键：网络抖动时不阻塞容器写日志
      max-buffer-size: 4m
YAML
echo ""
echo "然后 deploy-env.sh $ENV_NAME 重新部署，再用下面的命令验证："
echo "  aws logs describe-log-streams --region $REGION --log-group-name $LOG_GROUP --query 'logStreams[].logStreamName'"
echo ""
echo "查询整个环境的日志（Logs Insights）："
echo "  https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:logs-insights"
echo "  选日志组 $LOG_GROUP，然后："
echo "    fields @timestamp, @logStream, @message | sort @timestamp desc | limit 100"
echo "  只看某个服务：加一句 | filter @logStream like /backend-app/"
