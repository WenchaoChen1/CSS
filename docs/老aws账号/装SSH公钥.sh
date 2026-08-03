#!/usr/bin/env bash
# 给【老账号】021213872872 的实例装上我方 SSH 公钥（一次性开通访问用）。
#
# 背景：老账号的 dev / stage 实例没给过我方钥匙（只有 preprod 装了），而这些实例：
#   - 没有 IAM instance profile、没有 SSM 托管 → 走不了 Session Manager；
#   - 用的是客户自己的 key pair `css`，我方没有对应私钥。
# 所以用 **EC2 Instance Connect**（AWS 原生通道）破局：它把公钥临时（60 秒）推进实例的
# 授权列表，我们在这 60 秒内 SSH 进去，把公钥**永久**追加到 ~/.ssh/authorized_keys。
# 前置：实例是 Ubuntu 且预装 ec2-instance-connect（AWS 官方 Ubuntu AMI 默认有）；
#       调用者要有 ec2-instance-connect:SendSSHPublicKey 权限（Dev 用户在 Administrators 组，已具备）；
#       安全组 22 端口需放行本机出口 IP（实测 dev/stage 已放行）。
#
# 用法: ./装SSH公钥.sh <dev|stage|preprod|all> [公钥文件]
#   公钥缺省 ~/.ssh/wenchao.pub（与 源环境.env 里 *_KEY 对应的那把）
#   幂等：已存在同一公钥则跳过，不会重复追加。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

TARGET="${1:?用法: 装SSH公钥.sh <dev|stage|preprod|all> [公钥文件]}"
PUBKEY="${2:-$HOME/.ssh/wenchao.pub}"
[ -f "$PUBKEY" ] || { echo "[FATAL] 公钥不存在: $PUBKEY"; exit 1; }
# Windows/Git-Bash：aws.exe 是原生程序，file:// 必须给 Windows 形式路径，不能是 /c/... 的 MSYS 路径
if command -v cygpath >/dev/null 2>&1; then PUBKEY_W="$(cygpath -m "$PUBKEY")"; else PUBKEY_W="$PUBKEY"; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
# shellcheck disable=SC1090
set -a; . "$ENVF"; set +a
PROFILE="${SRC_AWS_PROFILE_ACTUAL:-css-client}"   # 本机实际 profile 名（源环境.env 里写的是 css-src，按需覆盖）
REGION="${SRC_AWS_REGION:-eu-central-1}"

aws_() { aws --profile "$PROFILE" --region "$REGION" --output text "$@" | tr -d '\r'; }

# 实例按 Name 标签查（老账号资源不归我们管，没有统一控制面标签可用）
inst_id() { aws_ ec2 describe-instances \
  --filters "Name=tag:Name,Values=css-$1" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId'; }

install_one() {  # $1=环境名 dev|stage|preprod
  local env="$1" id ip user az rc
  case "$env" in
    dev)     ip="$DEV_HOST";     user="${DEV_USER:-ubuntu}" ;;
    stage)   ip="$STAGE_HOST";   user="${STAGE_USER:-ubuntu}" ;;
    preprod) ip="$PREPROD_HOST"; user="${PREPROD_USER:-ubuntu}" ;;
    *) echo "未知环境 $env"; return 1 ;;
  esac
  id=$(inst_id "$env")
  [ -n "$id" ] && [ "$id" != "None" ] || { echo "[$env] ❌ 找不到运行中的 css-$env 实例"; return 1; }
  az=$(aws_ ec2 describe-instances --instance-ids "$id" --query 'Reservations[0].Instances[0].Placement.AvailabilityZone')
  echo "[$env] 实例 $id @ $az ($ip)"

  # 已经能连就不用折腾（幂等）
  if timeout 15 ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
       "$user@$ip" 'true' 2>/dev/null; then
    echo "[$env] ✅ 已可直接登录，检查公钥是否已在 authorized_keys…"
  else
    echo "[$env] 当前登录不了 → 用 EC2 Instance Connect 推临时公钥（有效 60 秒）"
    aws --profile "$PROFILE" --region "$REGION" ec2-instance-connect send-ssh-public-key \
      --instance-id "$id" --availability-zone "$az" --instance-os-user "$user" \
      --ssh-public-key "file://$PUBKEY_W" >/dev/null || {
        echo "[$env] ❌ SendSSHPublicKey 失败（实例可能没装 ec2-instance-connect 包）"; return 1; }
    echo "[$env] 临时公钥已推送，60 秒内完成永久安装"
  fi

  # 永久追加（幂等：按公钥主体去重）。
  # ⚠️ 只装「类型 + 密钥体」两段，**去掉 .pub 尾部的注释**（那里通常是 用户名@机器名 的个人标识，
  #   2026-08-03 要求：装到客户服务器上的公钥不得带个人标识）。
  local KEYBODY KEYLINE; KEYBODY=$(awk '{print $2}' "$PUBKEY"); KEYLINE=$(awk '{print $1" "$2}' "$PUBKEY")
  rc=$(timeout 30 ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "$user@$ip" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
     if grep -q '$KEYBODY' ~/.ssh/authorized_keys; then echo ALREADY; else echo '$KEYLINE' >> ~/.ssh/authorized_keys && echo ADDED; fi" 2>&1 | tail -1)
  case "$rc" in
    ADDED)   echo "[$env] ✅ 公钥已永久写入 authorized_keys" ;;
    ALREADY) echo "[$env] ✅ 公钥本就已在（跳过）" ;;
    *)       echo "[$env] ❌ 写入失败: $rc"; return 1 ;;
  esac

  # 复验：用普通 SSH（不依赖 Instance Connect 的 60 秒窗口）
  sleep 2
  if timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=12 "$user@$ip" 'echo OK; hostname' >/dev/null 2>&1; then
    echo "[$env] ✅ 复验通过：现在可用 $PUBKEY 对应的私钥直接登录"
  else
    echo "[$env] ⚠️ 复验未通过——若本机私钥带 passphrase，请先 ssh-add 后重试"
  fi
}

case "$TARGET" in
  all) for e in dev stage preprod; do install_one "$e" || true; echo; done ;;
  *)   install_one "$TARGET" ;;
esac

echo "===== 完成。后续拉取脚本（拉取数据库/docker-env/S3）即可对这些环境使用 ====="
