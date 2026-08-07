#!/usr/bin/env bash
# 一机一钥（凭证不跨机复用）：为每台服务器创建【专属】 EC2 key pair，私钥落到本机 ~/.ssh/<name>.pem，
# 再经 SSM 把「该机专属公钥 + 你的个人公钥（wenchao）」一起写进该机 ec2-user 的 authorized_keys。
#   css-test-app    → key pair css-test
#   css-uat-app     → key pair css-uat
#   css-non-prod-bastion（原名 css-non-prod-gw）→ key pair css-non-prod-gw（钥名沿用旧名，与 deploy-env/ssh/css-non-prod-gw.pem 一致）
#
# ⚠️ AWS 的私钥【只在创建那一刻返回一次】，之后再也取不到：本地 .pem 丢了只能删 key pair 重建。
# ⚠️ 实例的 KeyName 元数据是启动时属性，运行中的机器【改不了】（AWS 限制），所以控制台上
#    css-test-app/css-uat-app 仍显示 KeyName=wenchao。这不影响实际登录——决定谁能登录的是
#    机器上的 authorized_keys，本脚本写的就是它。要让元数据也一致只能重建实例（没必要）。
#
# 用法: ./create-instance-keys.sh [个人公钥文件] [只处理某台（按 key pair 名）: css-test|css-uat|css-non-prod-gw]
#   例: ./create-instance-keys.sh                       # 三台全做，个人公钥默认 ~/.ssh/wenchao.pub
#       ./create-instance-keys.sh ~/.ssh/wenchao.pub css-uat
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

PERSONAL_PUB="${1:-$HOME/.ssh/wenchao.pub}"
ONLY="${2:-}"
REGION="us-east-1"
KEYDIR="$HOME/.ssh"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

[ -f "$PERSONAL_PUB" ] || { echo "个人公钥不存在: $PERSONAL_PUB"; exit 1; }
PERSONAL_LINE="$(tr -d '\r\n' < "$PERSONAL_PUB")"
PERSONAL_NAME="$(basename "$PERSONAL_PUB" .pub)"

# 实例名:key pair 名
# support-ref（2026-08-07 加）：实例由 css-terraform 以 key_name=css-support-ref 新建——建机前先跑本脚本
# 生成 key pair（实例还不存在时本脚本只建钥、跳过 authorized_keys 写入，新机 cloud-init 会自动装公钥）。
PAIRS="css-test-app:css-test css-uat-app:css-uat css-support-ref-app:css-support-ref css-non-prod-bastion:css-non-prod-gw"

for entry in $PAIRS; do
  INST_NAME="${entry%%:*}"; KEYNAME="${entry##*:}"
  [ -n "$ONLY" ] && [ "$ONLY" != "$KEYNAME" ] && continue
  echo ""
  echo "===== $INST_NAME  (key pair: $KEYNAME) ====="
  PEM="$KEYDIR/$KEYNAME.pem"

  # ---- 1) 专属 key pair：不存在就创建并落盘私钥 ----
  if aws --region "$REGION" ec2 describe-key-pairs --key-names "$KEYNAME" >/dev/null 2>&1; then
    if [ -f "$PEM" ]; then
      echo "key pair 已存在且本地有私钥: $PEM"
    else
      echo "[WARN] AWS 上有 key pair $KEYNAME 但本地缺私钥 $PEM"
      echo "       私钥无法二次获取；要重建请先: aws ec2 delete-key-pair --region $REGION --key-name $KEYNAME 再跑本脚本"
      echo "       本轮跳过该机的专属公钥写入（个人公钥仍会补装）"
    fi
  else
    aws --region "$REGION" ec2 create-key-pair --key-name "$KEYNAME" --key-type ed25519 \
      --tag-specifications "ResourceType=key-pair,Tags=[{Key=Name,Value=$KEYNAME},{Key=Instance,Value=$INST_NAME}]" \
      --query 'KeyMaterial' --output text > "$PEM.raw"
    # Windows 换行会让 OpenSSH 报 libcrypto 错：强制 LF
    tr -d '\r' < "$PEM.raw" > "$PEM" && rm -f "$PEM.raw"
    chmod 600 "$PEM" 2>/dev/null || true
    echo "key pair 创建，私钥已保存: $PEM（只此一次，请勿丢失）"
  fi

  # ---- 2) 由私钥导出公钥 ----
  KEY_LINE=""
  if [ -f "$PEM" ]; then
    KEY_LINE="$(ssh-keygen -y -f "$PEM" 2>/dev/null | tr -d '\r\n') $KEYNAME"
    [ "${KEY_LINE:0:4}" = "ssh-" ] || { echo "[WARN] 从 $PEM 导出公钥失败，跳过专属公钥"; KEY_LINE=""; }
  fi

  # ---- 3) 找实例并确认 SSM 在线 ----
  ID=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=$INST_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId')
  [ "$ID" != "None" ] && [ -n "$ID" ] || { echo "[WARN] 找不到运行中的实例 $INST_NAME，跳过写入"; continue; }
  ONLINE=$(awsq ssm describe-instance-information --filters "Key=InstanceIds,Values=$ID" --query 'InstanceInformationList[0].PingStatus')
  [ "$ONLINE" = "Online" ] || { echo "[WARN] $INST_NAME ($ID) 未注册 SSM，跳过写入"; continue; }

  # ---- 4) 写 authorized_keys：专属公钥 + 个人公钥（幂等，去重）----
  ADD_CMDS="grep -qF '$PERSONAL_LINE' \$AK || echo '$PERSONAL_LINE' >> \$AK"
  [ -n "$KEY_LINE" ] && ADD_CMDS="grep -qF '${KEY_LINE%% *}' \$AK || echo '$KEY_LINE' >> \$AK
$ADD_CMDS"
  CMD="set -e
AK=/home/ec2-user/.ssh/authorized_keys
install -d -m 700 -o ec2-user -g ec2-user /home/ec2-user/.ssh
touch \$AK
$ADD_CMDS
chown ec2-user:ec2-user \$AK && chmod 600 \$AK
echo '当前 authorized_keys 条目:'
awk '{print \"  - \" \$1 \" \" substr(\$2,1,20) \"... \" \$3}' \$AK"

  PARAMS=$( (python3 - "$CMD" 2>/dev/null || python - "$CMD") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["600"]}))
PY
)
  CID=$(awsq ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
    --comment "install keys on $INST_NAME" --parameters "$PARAMS" --query 'Command.CommandId')
  for i in $(seq 1 30); do
    ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query Status 2>/dev/null || echo Pending)
    case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 5
  done
  echo "写入状态: $ST"
  awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardOutputContent 2>/dev/null || true
done

echo ""
echo "===== 完成：一机一钥 + 个人公钥（$PERSONAL_NAME）双通道 ====="
echo "专属钥登录（每台各自的私钥）:"
echo "  堡垒: ssh -i deploy-env/ssh/css-non-prod-gw.pem ec2-user@<堡垒EIP>"
echo "  test: ssh -i deploy-env/ssh/css-test.pem -o ProxyCommand='ssh -i deploy-env/ssh/css-non-prod-gw.pem -W %h:%p ec2-user@<堡垒EIP>' ec2-user@10.20.10.10"
echo "  uat : ssh -i deploy-env/ssh/css-uat.pem  -o ProxyCommand='ssh -i deploy-env/ssh/css-non-prod-gw.pem -W %h:%p ec2-user@<堡垒EIP>' ec2-user@10.20.11.10"
echo "个人钥登录（三台通用，应急/日常）: ssh -i ~/.ssh/$PERSONAL_NAME -J ec2-user@<堡垒EIP> ec2-user@<私网IP>"
