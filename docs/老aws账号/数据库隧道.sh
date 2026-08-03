#!/usr/bin/env bash
# 【本机 → 老账号 EC2 上的容器数据库】SSH 隧道，Navicat/DBeaver/psql 直连用。
# 与新账号的 05-数据库运维/db-tunnel.sh 的区别：那个连的是私网 RDS、必须经堡垒机跳板；
# 这里的库跑在 EC2 自己的 docker 容器里、EC2 有公网 IP——**直连该机，不走任何堡垒机**。
#
# 原理：容器的 5432 没有发布到宿主机端口，但容器 IP 在宿主机上可达；
#   脚本先 SSH 查出容器 IP，再开 -L <本地端口>:<容器IP>:5432 隧道。
#
# 用法: ./数据库隧道.sh <dev|stage|preprod> [main|ocr] [本地端口] [--check]
#   main = css-backend__db（业务主库，库名 postgres）      默认
#   ocr  = css-backend__ocr-db（OCR 库，库名 ocr_catalog）
#   本地端口缺省 5433；--check 只探测链路通不通，不驻留。
#   例:  ./数据库隧道.sh dev              # 之后客户端连 localhost:5433
#        ./数据库隧道.sh stage ocr 5434
# 私钥带 passphrase：前台运行会提示输入一次；批量/免交互场景先 ssh-add。
set -euo pipefail
export MSYS_NO_PATHCONV=1

ENV_NAME="${1:?用法: 数据库隧道.sh <dev|stage|preprod> [main|ocr] [本地端口] [--check]}"
WHICH="${2:-main}"
LPORT="${3:-5433}"
MODE="${4:-}"
[ "$WHICH" = "--check" ] && { MODE="--check"; WHICH=main; }
[ "$LPORT" = "--check" ] && { MODE="--check"; LPORT=5433; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
getv() { grep -m1 "^$1=" "$ENVF" | cut -d= -f2- | tr -d '"\r'; }
case "$ENV_NAME" in
  dev)     HOST=$(getv DEV_HOST);     USER_=$(getv DEV_USER) ;;
  stage)   HOST=$(getv STAGE_HOST);   USER_=$(getv STAGE_USER) ;;
  preprod) HOST=$(getv PREPROD_HOST); USER_=$(getv PREPROD_USER) ;;
  *) echo "[FATAL] 环境只能是 dev|stage|preprod"; exit 1 ;;
esac
USER_="${USER_:-ubuntu}"
case "$WHICH" in
  main) CTR=css-backend__db;     DBNAME=postgres ;;
  ocr)  CTR=css-backend__ocr-db; DBNAME=ocr_catalog ;;
  *) echo "[FATAL] 第二个参数只能是 main|ocr"; exit 1 ;;
esac

SSHOPT="-o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o ExitOnForwardFailure=yes"
echo "[i] 查询 $ENV_NAME ($HOST) 上 $CTR 的容器 IP…"
CIP=$(ssh $SSHOPT "$USER_@$HOST" \
  "docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' $CTR" | tr -d '\r' | awk '{print $1}')
[ -n "$CIP" ] || { echo "[FATAL] 拿不到容器 IP（容器没在跑？）"; exit 1; }

echo "======================================================"
echo " 客户端连接参数（隧道开着才有效）："
echo "   主机 localhost   端口 $LPORT   库 $DBNAME   用户 postgres"
echo "   密码：见 备份/docker镜像/$ENV_NAME/${CTR}.env 的 POSTGRES_PASSWORD"
echo "======================================================"

if [ "$MODE" = "--check" ]; then
  ssh $SSHOPT -f -N -L "$LPORT:$CIP:5432" "$USER_@$HOST"
  sleep 2
  if (exec 3<>"/dev/tcp/127.0.0.1/$LPORT") 2>/dev/null; then
    exec 3>&- 3<&-; echo "[--check] ✅ 隧道可建立、端口 $LPORT 可连（$ENV_NAME/$WHICH → $CIP:5432）"
  else
    echo "[--check] ❌ 端口 $LPORT 不通"; RC=1
  fi
  # 收掉后台隧道（按转发参数精确匹配，不误杀其它 ssh）
  if command -v pkill >/dev/null 2>&1; then pkill -f "ssh.*-L $LPORT:$CIP:5432" 2>/dev/null || true
  else ps | grep -F -- "-L $LPORT:$CIP:5432" | awk '{print $1}' | xargs -r kill 2>/dev/null || true; fi
  exit "${RC:-0}"
fi

echo "[i] 隧道启动（前台驻留，Ctrl+C 关闭）: localhost:$LPORT → $HOST → $CIP:5432"
exec ssh $SSHOPT -N -L "$LPORT:$CIP:5432" "$USER_@$HOST"
