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
# 续期: 同名重跑本脚本即可（复用同一把钥，只把 authorized_keys 条目的到期时间刷新为 今天+<天数>）
# 台账: 每次发放/续期自动追加到 ./dev-ssh发放记录.md（无密钥材料，入库）；实时有效状态用 revoke-dev-ssh.sh --list 查
# 撤销/查看: ./revoke-dev-ssh.sh
set -euo pipefail

DEV="${1:?用法: grant-dev-ssh.sh <开发者名> <有效天数> [nonprod|prod] [apps...]}"
DAYS="${2:?缺有效天数，如 30}"
[[ "$DEV" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "[FATAL] 开发者名只允许 字母/数字/_/-（会拼进远程命令与 authorized_keys 标签）"; exit 1; }
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "[FATAL] 有效天数必须是纯数字"; exit 1; }
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

# ⚠️ expiry-time 格式：**纯 12 位 YYYYMMDDHHMM，不带 "T"、不带 "Z"**。
# 踩坑记录（2026-08-03 实测定性，sshd 调试日志 "bad key options: invalid expires time"）：
#   ① 原先写成 ISO 风格 20260830T0808Z —— 非法，OpenSSH 会【拒绝整条 key】，表现为发出去的钥匙一律
#      Permission denied（此前发过的钥匙其实从未生效）；
#   ② 去掉 T 只留 Z 仍然失败 —— 本机 sshd 是 OpenSSH_8.7p1（AL2023），其 parse_absolute_time()
#      只接受 8/12/14 位纯数字，**不支持 Z（UTC）后缀**（Z 是更高版本才加的）。
# 不带 Z 时按【服务器本地时区】解释；三台目标机实测均为 UTC，故用 date -u 生成即语义正确。
EXPIRY=$(date -u -d "+${DAYS} days" +%Y%m%d%H%M 2>/dev/null || date -u -v+"${DAYS}"d +%Y%m%d%H%M)

echo "===== 发放开发者密钥：$DEV / $TARGET / 到期 $EXPIRY UTC ====="

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
  [ "$s" = "Success" ] || { echo "SSM 执行超时（状态 $s）"; return 1; }
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

# 2) 可选：应用机（可开 shell，同样带过期）。实例 ID 按 Name 标签动态查（机器由 TF 重建后 ID 会变，勿写死）
app_id() { aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=css-$1-app" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text | tr -d '\r'; }
if [ "$TARGET" = "prod" ] && [ ${#APPS[@]} -gt 0 ]; then
  # 防跨环境串钥：test/uat 应用机属非生产组，prod 的开发者钥绝不能装上去
  echo "⚠️ 目标是 prod，忽略 apps 参数 [${APPS[*]}]（test/uat 应用机属非生产组，不接受 prod 开发者钥）"
  APPS=()
fi
for app in "${APPS[@]}"; do
  case "$app" in test|uat) ;; *) echo "跳过未知应用机 [$app]（只支持 test/uat）"; continue ;; esac
  ID=$(app_id "$app")
  [ -n "$ID" ] && [ "$ID" != "None" ] || { echo "跳过 [$app]：找不到运行中的 css-$app-app"; continue; }
  APP_LINE="expiry-time=\"${EXPIRY}\",no-agent-forwarding,no-X11-forwarding ${PUB}"
  run_ssm "$ID" "set -e
f=/home/ec2-user/.ssh/authorized_keys
touch \"\$f\"
grep -v ' ${TAG}\$' \"\$f\" > \"\$f.tmp\" || true
printf '%s\n' '${APP_LINE}' >> \"\$f.tmp\"
mv \"\$f.tmp\" \"\$f\"; chmod 600 \"\$f\"; chown ec2-user:ec2-user \"\$f\"
echo '${app} 应用机条目已写入'"
done

# 3) 记入发放台账（不含任何密钥材料，可入库；实时有效状态以 revoke-dev-ssh.sh --list 为准）
LEDGER="$(cd "$(dirname "$0")" && pwd)/dev-ssh发放记录.md"
printf -- '- %s 发放/续期 `%s`（%s）到期 **%s**，范围=堡垒机%s\n' \
  "$(date -u +%F)" "$DEV" "$TARGET" "$EXPIRY" "${APPS[*]:+ + 应用机 ${APPS[*]}}" >> "$LEDGER"
echo "已记入台账: $LEDGER"

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
