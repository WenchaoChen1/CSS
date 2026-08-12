#!/usr/bin/env bash
# 一键打开【本机 → RDS】的 SSH 隧道，供 Navicat / DBeaver / psql 等客户端直连数据库（不经过应用代码）。
#
# 为什么必须隧道：RDS 在私有子网、无公网 IP，安全组只放行 VPC 内的 app-sg 与堡垒机 SG——
# 本机无论如何都直连不到，只能经堡垒机转发（详见 ../本地连接数据库.md）。
#
# 用法:
#   ./db-tunnel.sh <test|uat|support-ref|support-demo|prod> [本地端口]     # 端口缺省 5433，前台运行，Ctrl+C 关闭
#   ./db-tunnel.sh test --check                   # 只探测隧道链路是否通（不驻留）
# 例:
#   ./db-tunnel.sh test            # 然后客户端连 localhost:5433 / 库 css-test-main / 用户 css_dev
#   ./db-tunnel.sh uat 5434        # 同时开 test 和 uat 两条隧道时用不同端口
#
# 账号密码见 ../运维访问速查.local.md（本脚本只建隧道，不碰任何凭证）。
set -uo pipefail

ENV_NAME="${1:?用法: db-tunnel.sh <test|uat|support-ref|support-demo|prod> [本地端口|--check]}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|prod"; exit 1 ;; esac
ARG2="${2:-5433}"
CHECK=0; [ "$ARG2" = "--check" ] && { CHECK=1; LPORT=5433; } || LPORT="$ARG2"
REGION=us-east-1
export MSYS_NO_PATHCONV=1 PYTHONUTF8=1

# ---- 目标：堡垒机 + RDS 实例（按环境组）。私钥集中在工作区 deploy-env/ssh/（2026-08-03 自 ~/.ssh 迁入）----
SSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../deploy-env/ssh" && pwd)"
case "$ENV_NAME" in
  test|uat|support-ref|support-demo) BASTION_IP=3.225.148.166;  KEY="$SSH_DIR/css-non-prod-gw.pem"; RDS_ID=css-non-prod ;;
  prod)                              BASTION_IP=34.225.237.45;  KEY="$SSH_DIR/css-prod-bastion";    RDS_ID=css-prod ;;
esac
# 允许用开发者临时钥：DEV_KEY=deploy-env/ssh/dev-keys/nonprod-xxx.pem ./db-tunnel.sh test
KEY="${DEV_KEY:-$KEY}"
[ -f "$KEY" ] || { echo "[FATAL] 找不到私钥 $KEY（管理员钥见 运维访问速查；开发者用 DEV_KEY=... 指定自己的钥）"; exit 1; }

# ---- RDS endpoint 动态查询（不写死，实例换了也不会过期）----
EP=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
       --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null | tr -d '\r')
if [ -z "$EP" ] || [ "$EP" = "None" ]; then
  echo "[FATAL] 查不到 RDS $RDS_ID 的地址。"
  [ "$ENV_NAME" = "prod" ] && echo "        prod RDS 由 enable_prod_compute 门控，尚未创建（见 css-terraform）。"
  exit 1
fi

# ---- 本地端口占用检查 ----
if (echo > "/dev/tcp/127.0.0.1/$LPORT") 2>/dev/null; then
  echo "[FATAL] 本机 $LPORT 端口已被占用（可能已有隧道在跑）。换个端口：./db-tunnel.sh $ENV_NAME 5434"
  exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes)

if [ "$CHECK" = 1 ]; then
  echo "探测 $ENV_NAME 链路（堡垒机 $BASTION_IP → $EP:5432）…"
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=12 -i "$KEY" -f -N -L "$LPORT:$EP:5432" ec2-user@"$BASTION_IP" || {
    echo "❌ SSH 到堡垒机失败：检查 ① 本机出口 IP 是否在 22 端口白名单 ② 私钥是否正确/未过期"; exit 1; }
  sleep 2
  if (echo > "/dev/tcp/127.0.0.1/$LPORT") 2>/dev/null; then echo "✅ 链路通（隧道可正常建立）"; RC=0; else echo "❌ 端口未就绪"; RC=1; fi
  pkill -f "$LPORT:$EP:5432" 2>/dev/null
  exit $RC
fi

cat <<EOT
===== 隧道：本机 localhost:$LPORT  →  $RDS_ID（经堡垒机 $BASTION_IP）=====
客户端（Navicat / DBeaver / psql）这样填：
  主机 Host      : localhost
  端口 Port      : $LPORT
  数据库 Database: css-$ENV_NAME-main   （OCR 库填 css-$ENV_NAME-ocr）
  用户 Username  : css_dev              （日常开发推荐；运维全权用 css_ops；应用账号 css_app_$ENV_NAME）
  密码 Password  : 见 ../运维访问速查.local.md
  SSL            : 不用开（流量已在 SSH 隧道内加密）

命令行示例：
  psql -h localhost -p $LPORT -U css_dev -d css-$ENV_NAME-main
  docker run --rm -it -e PGPASSWORD=<密码> postgres:16 psql -h host.docker.internal -p $LPORT -U css_dev -d css-$ENV_NAME-main

隧道保持在前台运行，**Ctrl+C 关闭**。断线会自动保活重试（ServerAlive）。
EOT

exec ssh "${SSH_OPTS[@]}" -i "$KEY" -N -L "$LPORT:$EP:5432" ec2-user@"$BASTION_IP"
