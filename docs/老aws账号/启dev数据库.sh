#!/usr/bin/env bash
# 恢复【老账号】dev 机（3.124.149.172）上被 停dev数据库.sh 停掉的两个数据库容器：
#   css-backend__db（主库 postgres）+ css-backend__ocr-db（OCR 库 ocr_catalog）
# 动作 = 停dev数据库.sh 头部记载的官方回滚：restart 策略改回 always + docker start。
# 数据卷一直原地保留，启动后老环境（app/worker/cron）自行重连恢复。
#
# 用法: SSH_KEY_PASSPHRASE=<口令> ./启dev数据库.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
set -a; . "$ENVF"; set +a
TGT="${DEV_USER:-ubuntu}@$DEV_HOST"
CTRS="css-backend__db css-backend__ocr-db"

# ---- ssh-agent：一次解锁全程复用（同 拉取三环境.sh）----
KEY_RAW="$(grep -m1 '^DEV_KEY=' "$ENVF" | cut -d= -f2- | tr -d '"'"'"'\r')"
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

echo "== 启动前状态 =="
$SSH "$TGT" "docker ps -a --filter name=css-backend__db --filter name=css-backend__ocr-db --format '{{.Names}}|{{.Status}}'"

echo "== restart 策略改回 always（还原 停dev数据库.sh 的改动）=="
$SSH "$TGT" "docker update --restart=always $CTRS"

echo "== docker start =="
$SSH "$TGT" "docker start $CTRS"

echo "== 启动后核验（等健康检查 30 秒）=="
$SSH "$TGT" "sleep 30
for c in $CTRS; do
  st=\$(docker inspect -f '{{.State.Status}}' \$c)
  rp=\$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' \$c)
  hl=\$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}无健康检查{{end}}' \$c)
  echo \"\$c: state=\$st restart=\$rp health=\$hl\"
  [ \"\$st\" = running ] || { echo \"[FATAL] \$c 未运行\"; exit 1; }
  [ \"\$rp\" = always ] || { echo \"[FATAL] \$c 重启策略未还原为 always\"; exit 1; }
done"

echo "===== 完成：两库容器已启动、restart 策略已还原为 always ====="
