#!/usr/bin/env bash
# 撤销/查看堡垒机上的开发者 SSH 条目（配合 grant-dev-ssh.sh 使用）。
# 用法:
#   ./revoke-dev-ssh.sh --list [nonprod|prod]        # 列出所有开发者条目及到期时间
#   ./revoke-dev-ssh.sh <开发者名> [nonprod|prod]     # 立即撤销某开发者（不等到期）
set -euo pipefail

REGION=us-east-1
ARG1="${1:?用法: revoke-dev-ssh.sh <开发者名|--list> [nonprod|prod]}"
TARGET="${2:-nonprod}"
case "$TARGET" in
  nonprod) INSTANCE=i-08b0ef319d08eae38 ;;
  prod)    INSTANCE=i-0a6d6754c61c239d0 ;;
  *) echo "第二个参数只能是 nonprod 或 prod"; exit 1 ;;
esac

if [ "$ARG1" = "--list" ]; then
  REMOTE_CMD='grep -o "expiry-time=\"[^\"]*\".*dev-[A-Za-z0-9_-]*$" /home/ec2-user/.ssh/authorized_keys | sed "s/.*expiry-time=\"\([^\"]*\)\".* \(dev-.*\)/\2 到期 \1/" || echo "(无开发者条目)"'
else
  TAG="dev-${ARG1}"
  REMOTE_CMD="set -e
f=/home/ec2-user/.ssh/authorized_keys
before=\$(wc -l < \"\$f\")
grep -v ' ${TAG}\$' \"\$f\" > \"\$f.tmp\" || true
mv \"\$f.tmp\" \"\$f\"; chmod 600 \"\$f\"; chown ec2-user:ec2-user \"\$f\"
after=\$(wc -l < \"\$f\")
echo \"已撤销 ${TAG}：条目 \$before → \$after\""
fi

CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters "$(node -e "console.log(JSON.stringify({commands:[process.argv[1]]}))" "$REMOTE_CMD")" \
  --query 'Command.CommandId' --output text)
for _ in $(seq 1 30); do
  S=$(aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" --details \
        --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo Pending)
  case "$S" in Success) break;; Failed|Cancelled|TimedOut) echo "SSM 执行失败: $S"; exit 1;; esac
  sleep 2
done
aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text

echo
echo "提示: 本地私钥 ./dev-keys/${TARGET}-${ARG1}.pem 可一并删除（撤销后已无用）"
