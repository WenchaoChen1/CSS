#!/usr/bin/env bash
# 停止【老账号】preprod 机（3.74.51.100，产品环境）上的【前端 + kafka + rabbitmq】容器。
# 背景（2026-08-22 产品切换到新账号 prod）：切换第一步——停前端（用户不能再操作）+ 停队列
# （异步消息不再产生/消费），冻结新写入后再拉最终备份。app/db 等其余容器按用户指令【不动】。
# 与 停dev数据库.sh 同一套路：
#   - 手工 stop 的 always 容器会随 dockerd/EC2 重启复活，停完必须 docker update 改 unless-stopped；
#   - 数据/镜像原地保留，回滚 = docker update --restart=always + docker start，秒级满血。
#
# 用法:
#   SSH_KEY_PASSPHRASE=<口令> ./停preprod产品服务.sh            # 默认 dry-run：只列出将停的容器
#   SSH_KEY_PASSPHRASE=<口令> ASSUME_YES=1 ./停preprod产品服务.sh --stop   # 实际停止
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
set -a; . "$ENVF"; set +a
TGT="${PREPROD_USER:-ubuntu}@$PREPROD_HOST"
# 匹配模式：前端（实名 css-front-container）/ kafka+kafka-ui / rabbitmq —— 实名单以远端 docker ps 实测为准
PATTERN='front|kafka|zookeeper|rabbit'
DO_STOP=0
[ "${1:-}" = "--stop" ] && DO_STOP=1

# ---- ssh-agent：一次解锁全程复用（Windows ssh-agent 服务 Disabled，同 拉取三环境.sh）----
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

echo "== preprod 全部运行中容器 =="
$SSH "$TGT" "docker ps --format '{{.Names}}|{{.Status}}'"
CTRS=$($SSH "$TGT" "docker ps --format '{{.Names}}' | grep -Ei '$PATTERN' | tr '\n' ' '")
echo ""
echo "== 匹配将停清单（模式 $PATTERN）: ${CTRS:-<无匹配>} =="
[ -n "$CTRS" ] || { echo "[FATAL] 没有匹配到任何容器，核对模式"; exit 1; }

if [ "$DO_STOP" != "1" ]; then
  echo "===== DRY-RUN 结束（未停止任何容器）。确认清单无误后加 --stop 实际执行 ====="
  exit 0
fi

if [ "${ASSUME_YES:-0}" != "1" ]; then
  read -r -p "将停止 $TGT 上的: $CTRS 并改 restart=unless-stopped。输入 yes 继续: " ans
  [ "$ans" = "yes" ] || { echo "已取消"; exit 1; }
fi

echo "== docker stop -t 60 =="
$SSH "$TGT" "docker stop -t 60 $CTRS"
echo "== 改 restart 策略 → unless-stopped（防 daemon 重启复活）=="
$SSH "$TGT" "docker update --restart=unless-stopped $CTRS"
echo "== 停止后核验 =="
$SSH "$TGT" "for c in $CTRS; do
  st=\$(docker inspect -f '{{.State.Status}}' \$c); rp=\$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' \$c)
  echo \"\$c: state=\$st restart=\$rp\"
  [ \"\$st\" = exited ] || { echo \"[FATAL] \$c 未停止\"; exit 1; }
done"
echo "===== 完成。回滚: ssh $TGT 'docker update --restart=always $CTRS && docker start $CTRS' ====="
