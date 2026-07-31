#!/usr/bin/env bash
# 撤销/查看开发者 SSH 条目（堡垒机 + test/uat 应用机一并处理；配合 grant-dev-ssh.sh）。
# 用法:
#   ./revoke-dev-ssh.sh --list [nonprod|prod]        # 列出各机器的开发者条目及到期时间
#   ./revoke-dev-ssh.sh <开发者名> [nonprod|prod]     # 立即撤销（不等到期）
set -euo pipefail

REGION=us-east-1
ARG1="${1:?用法: revoke-dev-ssh.sh <开发者名|--list> [nonprod|prod]}"
TARGET="${2:-nonprod}"

case "$TARGET" in
  nonprod) MACHINES=("堡垒机:i-08b0ef319d08eae38" "test:i-0b3e73ed51811b69c" "uat:i-00c635f52140cf035") ;;
  prod)    MACHINES=("堡垒机:i-0a6d6754c61c239d0") ;;
  *) echo "第二个参数只能是 nonprod 或 prod"; exit 1 ;;
esac

json_cmd() { node -e "console.log(JSON.stringify({commands:[process.argv[1]]}))" "$1"; }
run_ssm() {
  local cid s
  cid=$(aws ssm send-command --region "$REGION" --instance-ids "$1" \
    --document-name AWS-RunShellScript --parameters "$(json_cmd "$2")" \
    --query 'Command.CommandId' --output text)
  for _ in $(seq 1 30); do
    s=$(aws ssm list-command-invocations --region "$REGION" --command-id "$cid" \
          --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo Pending)
    case "$s" in Success) break;; Failed|Cancelled|TimedOut) echo "  (SSM 失败: $s)"; return 0;; esac
    sleep 2
  done
  aws ssm list-command-invocations --region "$REGION" --command-id "$cid" --details \
    --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text
}

for m in "${MACHINES[@]}"; do
  NAME="${m%%:*}"; ID="${m##*:}"
  echo "===== $NAME ($ID) ====="
  if [ "$ARG1" = "--list" ]; then
    run_ssm "$ID" 'grep -oE "expiry-time=\"[^\"]*\".* dev-[A-Za-z0-9_-]+$" /home/ec2-user/.ssh/authorized_keys 2>/dev/null | sed -E "s/.*expiry-time=\"([^\"]*)\".* (dev-.*)/\2 到期 \1/" || echo "(无开发者条目)"'
  else
    TAG="dev-${ARG1}"
    run_ssm "$ID" "set -e
f=/home/ec2-user/.ssh/authorized_keys
[ -f \"\$f\" ] || { echo '(无文件)'; exit 0; }
before=\$(grep -c ' ${TAG}\$' \"\$f\" || true)
grep -v ' ${TAG}\$' \"\$f\" > \"\$f.tmp\" || true
mv \"\$f.tmp\" \"\$f\"; chmod 600 \"\$f\"; chown ec2-user:ec2-user \"\$f\"
echo \"撤销 ${TAG}: 删除 \$before 条\""
  fi
done

[ "$ARG1" = "--list" ] || echo "提示: 本地私钥 ./dev-keys/${TARGET}-${ARG1}.pem 可一并删除"
