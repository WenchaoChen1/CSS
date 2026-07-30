#!/usr/bin/env bash
# 把本机 SSH 公钥装进 AWS：① 导入为 EC2 key pair（新建实例用 --key-name 引用）；
#                        ② 可选：经 SSM 把公钥追加到【已存在实例】的 ec2-user authorized_keys
#                           （已建实例无法事后绑 key pair，只能这样补；网关机就是这种情况）。
# 用法: ./setup-ssh-key.sh [公钥文件] [实例名或ID ...]
#   例: ./setup-ssh-key.sh ~/.ssh/wenchao.pub                     # 只导入 key pair
#       ./setup-ssh-key.sh ~/.ssh/wenchao.pub css-non-prod-gw      # 导入 + 装到网关机
# key pair 名 = 公钥文件名去掉 .pub（wenchao.pub → wenchao）。幂等：指纹一致则跳过。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

PUB="${1:-$HOME/.ssh/wenchao.pub}"
shift || true
REGION="us-east-1"
[ -f "$PUB" ] || { echo "公钥文件不存在: $PUB"; exit 1; }
KEYNAME="$(basename "$PUB" .pub)"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

# ---- ① 导入 EC2 key pair ----
if aws --region "$REGION" ec2 describe-key-pairs --key-names "$KEYNAME" >/dev/null 2>&1; then
  echo "key pair 已存在: $KEYNAME（如需换公钥请先手工删除同名 key pair）"
else
  # aws.exe 读中文/长路径易出错：拷到 ASCII 临时路径再引用
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  cp "$PUB" "$TMP/key.pub"
  if command -v cygpath >/dev/null 2>&1; then TMPF="$(cygpath -m "$TMP")"; else TMPF="$TMP"; fi
  aws --region "$REGION" ec2 import-key-pair --key-name "$KEYNAME" \
    --public-key-material "fileb://$TMPF/key.pub" \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$KEYNAME}]" >/dev/null
  echo "key pair 导入: $KEYNAME"
fi
aws --region "$REGION" ec2 describe-key-pairs --key-names "$KEYNAME" \
  --query 'KeyPairs[0].{name:KeyName,type:KeyType,fingerprint:KeyFingerprint}' --output json | tr -d '\r'

# ---- ② 给已存在实例补装公钥（经 SSM，不需要已有 SSH 通道）----
PUBLINE="$(tr -d '\r\n' < "$PUB")"
for target in "$@"; do
  if [[ "$target" == i-* ]]; then ID="$target"; else
    ID=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=$target" "Name=instance-state-name,Values=running" \
      --query 'Reservations[0].Instances[0].InstanceId')
  fi
  [ "$ID" != "None" ] && [ -n "$ID" ] || { echo "跳过（找不到运行中的实例）: $target"; continue; }
  ONLINE=$(awsq ssm describe-instance-information --filters "Key=InstanceIds,Values=$ID" --query 'InstanceInformationList[0].PingStatus')
  [ "$ONLINE" = "Online" ] || { echo "跳过（未注册 SSM）: $target $ID"; continue; }

  CMD="install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.ssh
touch /home/ec2-user/.ssh/authorized_keys
grep -qF '$PUBLINE' /home/ec2-user/.ssh/authorized_keys || echo '$PUBLINE' >> /home/ec2-user/.ssh/authorized_keys
chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys
chmod 600 /home/ec2-user/.ssh/authorized_keys
echo '已装公钥数:' \$(wc -l < /home/ec2-user/.ssh/authorized_keys)"
  PARAMS=$( (python3 - "$CMD" 2>/dev/null || python - "$CMD") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["600"]}))
PY
)
  CID=$(awsq ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
    --comment "install ssh pubkey $KEYNAME" --parameters "$PARAMS" --query 'Command.CommandId')
  for i in $(seq 1 30); do
    ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query Status 2>/dev/null || echo Pending)
    case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 5
  done
  OUT=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardOutputContent 2>/dev/null || echo "")
  echo "$target ($ID): $ST — $OUT"
done

echo "===== 完成 ====="
echo "新建实例引用: create-app-ec2.sh <env> [type] [keypair]（默认就用 $KEYNAME）"
echo "登录（私网机只能经堡垒机跳）: ssh -J ec2-user@<堡垒EIP> -i ~/.ssh/$KEYNAME ec2-user@<私网IP>"
