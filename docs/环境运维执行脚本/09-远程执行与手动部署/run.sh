#!/usr/bin/env bash
# 经 AWS SSM Run Command 在目标环境 EC2 上执行命令（免 SSH/22 端口），等待完成并回显输出。
# 目标机按标签 Environment=css-<env> 定位（且 SSM Online）。命令经 JSON 安全编码，支持引号/多行/特殊字符。
# 用法: ./run.sh <test|uat|prod> '<shell 命令>'   （与 Backend 仓库 deploy/aws/ssm-run.sh 同源）
#   另: ./run.sh --instance <i-xxxx> '<命令>'  —— 直接指定实例，用于【堡垒机】等标签 css-shared 的机器
#       （按 Environment=css-<env> 定位取不到它们；05-数据库运维 的删库/恢复类脚本要用）
set -euo pipefail

# 中文 Windows 上 python 默认 GBK 编码 stdout，回显含中文/emoji 的远程输出会 UnicodeEncodeError（2026-08-11）
export PYTHONUTF8=1

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
# python 探测必须【实际执行】验证（2026-08-07 修）：Windows 的 WindowsApps 目录自带
# python/python3 商店占位 stub，command -v 能找到但一执行就 exit 49——被它坑过。
PY=""
for _cand in python3 python; do
  if "$_cand" -c "1" >/dev/null 2>&1; then PY="$_cand"; break; fi
done
[ -n "$PY" ] || { echo "需要可用的 python（当前 PATH 里只有 Microsoft Store 占位 stub 或没有 python）"; exit 1; }

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

# 用 python 生成 JSON 参数，命令内容任意字符都安全。
# ⚠️ 参数经【临时文件】传给 aws（2026-08-07 修）：deploy-env.sh 的 bundle base64 有 ~27KB，
# 作为命令行参数会顶到 Windows 32K 命令行上限，aws.exe 直接起不来（exit 49）。
# 文件放当前目录用相对路径引用——Git Bash 的 /tmp 绝对路径 Windows 版 aws.exe 解析不了。
PARAMS_FILE=".ssm-params-$$.json"
trap 'rm -f "$PARAMS_FILE"' EXIT
CMD="$CMD" "$PY" -c 'import json,os; print(json.dumps({"commands":[os.environ["CMD"]],"executionTimeout":["3600"]}))' > "$PARAMS_FILE"

CMD_ID=$(aws ssm send-command --region "$REGION" \
  --document-name AWS-RunShellScript \
  --instance-ids $IDS \
  --comment "css-cicd $ENV_NAME" \
  --parameters "file://$PARAMS_FILE" \
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
