#!/usr/bin/env bash
# 停止【老账号 021213872872】某环境上指定类别的 docker 容器（退役/冻结用）。
#
# 背景（2026-08-22 起分批退役老账号）：产品已切到新账号 prod。老账号各环境按批次停服，
# 停的顺序是「先停外部入口与队列，再停数据库」——数据库最后停，便于中途还能补拉备份。
#   · 已停：preprod 的 前端 / kafka / kafka-ui / rabbitmq（见同目录 停preprod产品服务.sh）
#   · 本脚本负责：dev/stage 的 kafka+mq+两个数据库，以及 preprod 的两个数据库
#
# 与 停dev数据库.sh / 停preprod产品服务.sh 的关系：那两个是单一用途的先行脚本；本脚本把
# 「环境 × 类别」参数化，避免每停一批就复制一个新脚本。三者停容器的手法完全一致：
#   ① docker stop -t 60（给 PG 留 checkpoint 时间）
#   ② docker update --restart=unless-stopped —— 【关键】手工 stop 的 restart=always 容器
#      会随 dockerd/EC2 重启复活，不改策略等于没停
#   ③ 逐个 inspect 核验 state=exited
# 数据卷与镜像原地保留 → 回滚 = docker update --restart=always + docker start，秒级满血。
#
# ⚠️ 影响面：停 db 会让该环境的应用**立即不可用**（老团队若还在用 dev/stage 会直接受影响）。
#    停之前确认该环境的数据已经拉走（docs/老aws账号/拉取三环境.sh <env> db）。
#
# 用法:
#   SSH_KEY_PASSPHRASE=<口令> ./停老环境容器.sh <dev|stage|preprod> <kafka-mq|db|kafka-mq-db>            # dry-run
#   SSH_KEY_PASSPHRASE=<口令> ASSUME_YES=1 ./停老环境容器.sh <dev|stage|preprod> <类别> --stop            # 实际停止
# 例:
#   ./停老环境容器.sh dev     kafka-mq-db --stop    # dev 的 kafka/mq/两个库
#   ./停老环境容器.sh preprod db          --stop    # preprod 只停两个库
#
# 类别 → 容器名匹配模式（实名单以远端 docker ps 实测为准，dry-run 会打印全量容器供核对）:
#   kafka-mq     kafka | zookeeper | rabbit
#   db           __db  | __ocr-db          （老栈库容器实名 css-backend__db / css-backend__ocr-db）
#   kafka-mq-db  以上两者
set -euo pipefail
export MSYS_NO_PATHCONV=1

ENV_NAME="${1:?用法: 停老环境容器.sh <dev|stage|preprod> <kafka-mq|db|kafka-mq-db> [--stop]}"
WHAT="${2:?缺类别: kafka-mq | db | kafka-mq-db}"
DO_STOP=0
[ "${3:-}" = "--stop" ] && DO_STOP=1

case "$ENV_NAME" in dev|stage|preprod) ;; *) echo "[FATAL] 环境必须是 dev|stage|preprod"; exit 1 ;; esac
case "$WHAT" in
  kafka-mq)    PATTERN='kafka|zookeeper|rabbit' ;;
  db)          PATTERN='__db|__ocr-db' ;;
  kafka-mq-db) PATTERN='kafka|zookeeper|rabbit|__db|__ocr-db' ;;
  *) echo "[FATAL] 类别必须是 kafka-mq | db | kafka-mq-db"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
set -a; . "$ENVF"; set +a

case "$ENV_NAME" in
  dev)     TGT="${DEV_USER:-ubuntu}@$DEV_HOST" ;;
  stage)   TGT="${STAGE_USER:-ubuntu}@$STAGE_HOST" ;;
  preprod) TGT="${PREPROD_USER:-ubuntu}@$PREPROD_HOST" ;;
esac

# ---- ssh-agent：一次解锁全程复用（Windows ssh-agent 服务 Disabled，同 拉取三环境.sh）----
# 源环境.env 里的 *_KEY 是 Windows 路径，不能用 source 后的值（bash 会吃掉 \U 之类转义），原样 grep + cygpath。
KEY_RAW="$(grep -m1 '^PREPROD_KEY=' "$ENVF" | cut -d= -f2- | tr -d '"'"'"'\r')"
if [ -n "$KEY_RAW" ] && command -v cygpath >/dev/null 2>&1; then KEY="$(cygpath -u "$KEY_RAW")"; else KEY="${KEY_RAW:-$HOME/.ssh/wenchao}"; fi
[ -f "$KEY" ] || KEY="$HOME/.ssh/wenchao"
[ -f "$KEY" ] || { echo "[FATAL] 私钥不存在: $KEY_RAW"; exit 1; }
eval "$(ssh-agent -s)" >/dev/null
trap 'ssh-agent -k >/dev/null 2>&1 || true; rm -f "${ASKPASS:-}"' EXIT
if [ -n "${SSH_KEY_PASSPHRASE:-}" ]; then
  ASKPASS="$(mktemp)"; printf '#!/bin/sh\nprintf %%s "%s"\n' "$SSH_KEY_PASSPHRASE" > "$ASKPASS"; chmod 700 "$ASKPASS"
  DISPLAY=1 SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force ssh-add "$KEY" >/dev/null 2>&1 \
    || { echo "[FATAL] 私钥口令错误"; exit 1; }
else
  echo "[i] 解锁私钥 $KEY（口令输入一次，全程复用）"
  ssh-add "$KEY" || { echo "[FATAL] 私钥加载失败"; exit 1; }
fi
SSH="ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new"

echo "===== 老账号 $ENV_NAME（$TGT）｜类别 $WHAT ====="
echo "== 全部运行中容器 =="
$SSH "$TGT" "docker ps --format '{{.Names}}|{{.Status}}|{{.Image}}'"
CTRS=$($SSH "$TGT" "docker ps --format '{{.Names}}' | grep -Ei '$PATTERN' | tr '\n' ' '")
echo ""
echo "== 匹配将停清单（模式 $PATTERN）: ${CTRS:-<无匹配>} =="
[ -n "${CTRS// /}" ] || { echo "[FATAL] 没有匹配到任何运行中容器，核对模式或该批已停"; exit 1; }

if [ "$DO_STOP" != "1" ]; then
  echo "===== DRY-RUN 结束（未停止任何容器）。确认清单无误后加 --stop 实际执行 ====="
  exit 0
fi

if [ "${ASSUME_YES:-0}" != "1" ]; then
  read -r -p "将停止 $TGT 上的: $CTRS 并改 restart=unless-stopped。输入 yes 继续: " ans
  [ "$ans" = "yes" ] || { echo "已取消"; exit 1; }
fi

echo "== docker stop -t 60（PG 需要时间做 checkpoint，别缩短）=="
$SSH "$TGT" "docker stop -t 60 $CTRS"
echo "== 改 restart 策略 → unless-stopped（防 daemon/EC2 重启复活）=="
$SSH "$TGT" "docker update --restart=unless-stopped $CTRS"
echo "== 停止后核验 =="
$SSH "$TGT" "for c in $CTRS; do
  st=\$(docker inspect -f '{{.State.Status}}' \$c); rp=\$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' \$c)
  echo \"\$c: state=\$st restart=\$rp\"
  [ \"\$st\" = exited ] || { echo \"[FATAL] \$c 未停止\"; exit 1; }
done"
echo "===== 完成。回滚: ssh $TGT 'docker update --restart=always $CTRS && docker start $CTRS' ====="
