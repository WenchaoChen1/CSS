#!/usr/bin/env bash
# 给开发人员发放【带过期时间】的 SSH 密钥（堡垒机必装；可选同时装到应用机）。
#
# 原理：OpenSSH authorized_keys 的 expiry-time 选项（AL2023 自带 OpenSSH ≥8.7 支持）——
#   到期后条目自动失效，无需人工清理。堡垒机条目额外加 no-pty + permitopen（纯跳板，
#   不能在堡垒机开 shell、只能转发到白名单目标）；应用机条目可正常开 shell。
#
# 用法:
#   ./grant-dev-ssh.sh <开发者名> <有效天数> [nonprod|prod] [apps...]
#     apps 可选：test uat —— 把同一把钥匙也装到对应应用机（同样带过期）。
#     不带 apps：开发者只能到堡垒机做隧道/跳板（够用 RDS/kafka-ui 场景），登不进应用机。
#   例:
#     ./grant-dev-ssh.sh zhangsan 30                 # 非生产堡垒机，30 天，仅隧道
#     ./grant-dev-ssh.sh zhangsan 30 nonprod test    # + 可登 test 应用机
#     ./grant-dev-ssh.sh zhangsan 14 prod            # 生产堡垒机
# 产物: ./dev-keys/<环境>-<开发者名>.pem（已 gitignore；安全渠道交付）
# 撤销/查看: ./revoke-dev-ssh.sh
set -euo pipefail

DEV="${1:?用法: grant-dev-ssh.sh <开发者名> <有效天数> [nonprod|prod] [apps...]}"
DAYS="${2:?缺有效天数，如 30}"
TARGET="${3:-nonprod}"
shift $(( $# >= 3 ? 3 : 2 ))
APPS=("$@")
REGION=us-east-1

case "$TARGET" in
  nonprod) INSTANCE=i-08b0ef319d08eae38; BASTION_IP=3.225.148.166
           PERMIT='permitopen="10.20.10.10:22",permitopen="10.20.11.10:22",permitopen="css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432"' ;;
  prod)    INSTANCE=i-0a6d6754c61c239d0; BASTION_IP=34.225.237.45
           PERMIT='permitopen="10.10.10.10:22"' ;;
  *) echo "第三个参数只能是 nonprod 或 prod"; exit 1 ;;
esac

KEYDIR="$(cd "$(dirname "$0")" && pwd)/dev-keys"
mkdir -p "$KEYDIR"
KEY="$KEYDIR/${TARGET}-${DEV}.pem"
TAG="dev-${DEV}"

EXPIRY=$(date -u -d "+${DAYS} days" +%Y%m%dT%H%M 2>/dev/null || date -u -v+"${DAYS}"d +%Y%m%dT%H%M)
EXPIRY="${EXPIRY}Z"

echo "===== 发放开发者密钥：$DEV / $TARGET / 到期 $EXPIRY (UTC) ====="

if [ -f "$KEY" ]; then
  echo "已存在 $KEY —— 复用（只刷新到期时间/目标机器）"
else
  ssh-keygen -t ed25519 -N "" -C "$TAG" -f "$KEY" -q
  chmod 600 "$KEY"
fi
PUB=$(cat "${KEY}.pub")

json_cmd() { node -e "console.log(JSON.stringify({commands:[process.argv[1]]}))" "$1"; }

run_ssm() { # $1=instance-id  $2=命令
  local cid
  cid=$(aws ssm send-command --region "$REGION" --instance-ids "$1" \
    --document-name AWS-RunShellScript --parameters "$(json_cmd "$2")" \
    --query 'Command.CommandId' --output text)
  local s
  for _ in $(seq 1 30); do
    s=$(aws ssm list-command-invocations --region "$REGION" --command-id "$cid" \
          --query 'CommandInvocations[0].Status' --output text 2>/dev/null || echo Pending)
    case "$s" in Success) break;; Failed|Cancelled|TimedOut)
      echo "SSM 执行失败($s):"; aws ssm list-command-invocations --region "$REGION" --command-id "$cid" --details \
        --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text; return 1;; esac
    sleep 2
  done
  aws ssm list-command-invocations --region "$REGION" --command-id "$cid" --details \
    --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text | tail -2
}

# 1) 堡垒机：纯跳板条目（no-pty + permitopen 白名单）
BASTION_LINE="${PERMIT},expiry-time=\"${EXPIRY}\",no-agent-forwarding,no-X11-forwarding,no-pty ${PUB}"
run_ssm "$INSTANCE" "set -e
f=/home/ec2-user/.ssh/authorized_keys
touch \"\$f\"
grep -v ' ${TAG}\$' \"\$f\" > \"\$f.tmp\" || true
printf '%s\n' '${BASTION_LINE}' >> \"\$f.tmp\"
mv \"\$f.tmp\" \"\$f\"; chmod 600 \"\$f\"; chown ec2-user:ec2-user \"\$f\"
echo '堡垒机条目已写入'"

# 2) 可选：应用机（可开 shell，同样带过期）
declare -A APP_ID=( [test]=i-0b3e73ed51811b69c [uat]=i-00c635f52140cf035 )
for app in "${APPS[@]}"; do
  ID="${APP_ID[$app]:-}"
  [ -n "$ID" ] || { echo "跳过未知应用机 [$app]（只支持 test/uat）"; continue; }
  APP_LINE="expiry-time=\"${EXPIRY}\",no-agent-forwarding,no-X11-forwarding ${PUB}"
  run_ssm "$ID" "set -e
f=/home/ec2-user/.ssh/authorized_keys
touch \"\$f\"
grep -v ' ${TAG}\$' \"\$f\" > \"\$f.tmp\" || true
printf '%s\n' '${APP_LINE}' >> \"\$f.tmp\"
mv \"\$f.tmp\" \"\$f\"; chmod 600 \"\$f\"; chown ec2-user:ec2-user \"\$f\"
echo '${app} 应用机条目已写入'"
done

cat <<EOT

===== 交付给开发者 =====
私钥: $KEY（安全渠道传递，勿走邮件/群聊明文）
到期: $EXPIRY UTC（自动失效；延期=重跑本脚本）

# RDS 隧道（Navicat/psql 连 localhost:5433）
ssh -i ${TARGET}-${DEV}.pem -N -L 5433:css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432 ec2-user@${BASTION_IP}
# 登应用机（需发钥时带了对应 apps 参数）
ssh -i ${TARGET}-${DEV}.pem -J ec2-user@${BASTION_IP} ec2-user@10.20.10.10   # test
ssh -i ${TARGET}-${DEV}.pem -J ec2-user@${BASTION_IP} ec2-user@10.20.11.10   # uat

撤销: ./revoke-dev-ssh.sh ${DEV} ${TARGET}（应用机条目同名 tag，一并撤）
EOT
