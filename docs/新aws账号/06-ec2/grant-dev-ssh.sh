#!/usr/bin/env bash
# 给开发人员发放【带过期时间】的堡垒机 SSH 密钥（不共用运维密钥，到期自动失效）。
#
# 原理：OpenSSH 的 authorized_keys 支持 expiry-time 选项（AL2023 自带 OpenSSH ≥8.7 支持）。
#   expiry-time="20261231T2359Z" → 到期后该条目直接不被接受，无需人工清理（清理只为整洁）。
# 同时限制为【纯跳板】：no-pty（不能在堡垒机上开 shell）+ permitopen 白名单（只能跳到应用机/RDS）。
#
# 用法:
#   ./grant-dev-ssh.sh <开发者名> <有效天数> [nonprod|prod]      # 发钥（默认 nonprod）
#   例: ./grant-dev-ssh.sh zhangsan 30
# 产物: ./dev-keys/<环境>-<开发者名>.pem（交给开发者，注意用安全渠道传递）
# 撤销/查看: 见同目录 revoke-dev-ssh.sh
set -euo pipefail

DEV="${1:?用法: grant-dev-ssh.sh <开发者名> <有效天数> [nonprod|prod]}"
DAYS="${2:?缺有效天数，如 30}"
TARGET="${3:-nonprod}"
REGION=us-east-1

case "$TARGET" in
  nonprod) INSTANCE=i-08b0ef319d08eae38; BASTION_IP=3.225.148.166
           # 允许跳转的内网目标（应用机 SSH + RDS 隧道）
           PERMIT='permitopen="10.20.10.10:22",permitopen="10.20.11.10:22",permitopen="css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432"' ;;
  prod)    INSTANCE=i-0a6d6754c61c239d0; BASTION_IP=34.225.237.45
           # prod 应用机/RDS 尚未创建，先只放规划中的应用机 IP；建成后按需补 permitopen
           PERMIT='permitopen="10.10.10.10:22"' ;;
  *) echo "第三个参数只能是 nonprod 或 prod"; exit 1 ;;
esac

KEYDIR="$(cd "$(dirname "$0")" && pwd)/dev-keys"
mkdir -p "$KEYDIR"
KEY="$KEYDIR/${TARGET}-${DEV}.pem"
TAG="dev-${DEV}"   # authorized_keys 里的注释，用于幂等替换与撤销

# 到期时间（UTC，带 Z 后缀避免时区歧义）
EXPIRY=$(date -u -d "+${DAYS} days" +%Y%m%dT%H%M 2>/dev/null || date -u -v+"${DAYS}"d +%Y%m%dT%H%M)
EXPIRY="${EXPIRY}Z"

echo "===== 发放开发者密钥 ====="
echo "开发者: $DEV   目标: $TARGET 堡垒机($BASTION_IP)   到期: $EXPIRY (UTC)"

# 1) 本地生成专属密钥对（无 passphrase，便于开发者脚本化；私钥只此一份）
if [ -f "$KEY" ]; then
  echo "已存在密钥 $KEY —— 复用它（只更新到期时间）"
else
  ssh-keygen -t ed25519 -N "" -C "$TAG" -f "$KEY" -q
  chmod 600 "$KEY"
fi
PUB=$(cat "${KEY}.pub")

# 2) 经 SSM 写入堡垒机 authorized_keys（幂等：先删同名条目再追加）
LINE="${PERMIT},expiry-time=\"${EXPIRY}\",no-agent-forwarding,no-X11-forwarding,no-pty ${PUB}"
REMOTE_CMD=$(cat <<EOS
set -e
f=/home/ec2-user/.ssh/authorized_keys
touch "\$f"; chmod 600 "\$f"; chown ec2-user:ec2-user "\$f"
grep -v ' ${TAG}\$' "\$f" > "\$f.tmp" || true
printf '%s\n' '${LINE}' >> "\$f.tmp"
mv "\$f.tmp" "\$f"; chmod 600 "\$f"; chown ec2-user:ec2-user "\$f"
echo "authorized_keys 现有开发者条目:"
grep -c 'expiry-time' "\$f" || true
EOS
)
CMD_ID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript \
  --parameters "$(python -c "import json,sys;print(json.dumps({'commands':[sys.argv[1]]}))" "$REMOTE_CMD" 2>/dev/null || node -e "console.log(JSON.stringify({commands:[process.argv[1]]}))" "$REMOTE_CMD")" \
  --query 'Command.CommandId' --output text)
for _ in $(seq 1 30); do
  S=$(aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" --details \
        --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo Pending)
  case "$S" in Success) break;; Failed|Cancelled|TimedOut) echo "SSM 执行失败: $S"; aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" --details --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text; exit 1;; esac
  sleep 2
done
aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" --details \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text

cat <<EOT

===== 交付给开发者的信息 =====
私钥文件: $KEY   （安全渠道传递，勿走邮件/群聊明文）
到期时间: $EXPIRY UTC —— 到期后自动失效，需要延期就重跑本脚本
连接方式（该密钥【只能做跳板】，不能在堡垒机上开 shell）:

  # 连 test 应用机
  ssh -i ${TARGET}-${DEV}.pem -J ec2-user@${BASTION_IP} ec2-user@10.20.10.10
  # 本机 5433 → RDS（然后 Navicat/psql 连 localhost:5433）
  ssh -i ${TARGET}-${DEV}.pem -N -L 5433:css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432 ec2-user@${BASTION_IP}

注意: 开发者还需要目标应用机自己的密钥才能真正登入应用机；只给 RDS 隧道用途时无需额外密钥。
撤销: ./revoke-dev-ssh.sh ${DEV} ${TARGET}
EOT
