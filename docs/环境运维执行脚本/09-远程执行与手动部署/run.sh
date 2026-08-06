#!/usr/bin/env bash
# 经 AWS SSM Run Command 在目标环境 EC2 上执行命令（免 SSH/22 端口），等待完成并回显输出。
# 目标机按标签 Environment=css-<env> 定位（且 SSM Online）。命令经 JSON 安全编码，支持引号/多行/特殊字符。
# 用法: ./run.sh <test|uat|prod> '<shell 命令>'   （与 Backend 仓库 deploy/aws/ssm-run.sh 同源）
#   另: ./run.sh --instance <i-xxxx> '<命令>'  —— 直接指定实例，用于【堡垒机】等标签 css-shared 的机器
#       （按 Environment=css-<env> 定位取不到它们；05-数据库运维 的删库/恢复类脚本要用）
set -euo pipefail

if [ "${1:-}" = "--instance" ]; then
  INSTANCE_ID="${2:?缺实例 ID}"
  CMD="${3:?缺要执行的命令}"
  ENV_NAME="direct"
else
  ENV_NAME="${1:?用法: run.sh <test|uat|prod> '<命令>'  或  run.sh --instance <i-xxx> '<命令>'}"
  CMD="${2:?缺要执行的命令}"
  INSTANCE_ID=""
fi
REGION="${AWS_REGION:-us-east-1}"
PY=$(command -v python3 || command -v python) || { echo "需要 python"; exit 1; }

if [ -n "$INSTANCE_ID" ]; then
  # 指定实例：仍校验 SSM Online，免得命令挂在离线机上白等 20 分钟
  IDS=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' --output text | tr -d '\r')
  [ -n "$IDS" ] || { echo "[FAIL] 实例 $INSTANCE_ID 不在 SSM Online"; exit 1; }
else
  IDS=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=tag:Environment,Values=css-$ENV_NAME" \
    --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' --output text | tr -d '\r')
  [ -n "$IDS" ] || { echo "[FAIL] 没有 SSM Online 且标签 Environment=css-$ENV_NAME 的实例"; exit 1; }
fi
echo "目标实例: $IDS"

# 用 python 生成 JSON 参数，命令内容任意字符都安全
PARAMS=$(CMD="$CMD" "$PY" -c 'import json,os; print(json.dumps({"commands":[os.environ["CMD"]],"executionTimeout":["3600"]}))')

CMD_ID=$(aws ssm send-command --region "$REGION" \
  --document-name AWS-RunShellScript \
  --instance-ids $IDS \
  --comment "css-cicd $ENV_NAME" \
  --parameters "$PARAMS" \
  --query 'Command.CommandId' --output text | tr -d '\r')
echo "SSM CommandId: $CMD_ID"

for i in $(seq 1 240); do   # 最长等 20 分钟
  STATUS=$(aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" \
    --query 'CommandInvocations[].Status' --output text | tr -d '\r')
  case "$STATUS" in
    *InProgress*|*Pending*|"") sleep 5 ;;
    *) break ;;
  esac
done

FAILED=0
for id in $IDS; do
  echo "===== 实例 $id 输出 ====="
  aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$id" \
    --query '{status:Status,stdout:StandardOutputContent,stderr:StandardErrorContent}' --output json \
    | "$PY" -c 'import json,sys; d=json.load(sys.stdin); print(d["stdout"] or ""); print(d["stderr"] or "", file=sys.stderr); sys.exit(0 if d["status"]=="Success" else 1)' \
    || FAILED=1
done
[ "$FAILED" = 0 ] && echo "===== SSM 执行成功 =====" || { echo "[FAIL] SSM 执行失败"; exit 1; }
