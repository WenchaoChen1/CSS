#!/usr/bin/env bash
# 停止【老账号】dev 机（3.124.149.172，实为老团队 test 环境）上的两个数据库容器：
#   css-backend__db（主库 postgres）+ css-backend__ocr-db（OCR 库 ocr_catalog）
#
# 背景（2026-08-15 迁移切换排查结论）：
#   - 停库 = 掐住老环境咽喉：所有业务路径先过主库，库停则 app/worker/cron 全部失能、写入停止，
#     公网裸奔的 7432 也随之无监听。数据卷原地保留，回滚 = docker start，秒级满血。
#   - 两个 db 容器的 compose restart 策略是 always——手工 stop 的 always 容器在 dockerd/EC2
#     重启（含 unattended-upgrades 升 docker 包）后会被自动拉起，而其余容器都在跑，
#     db 一复活 = 整个老环境瞬间满血复活。所以停完必须 docker update 改成 unless-stopped
#     （只改重启策略、不重建容器、env 不丢，完全可逆）。
#   - 主库镜像 FROM postgres:16.1-alpine（官方基底 STOPSIGNAL=SIGINT=fast shutdown，
#     主动断开连接、干净落盘），-t 120 只是保险。
#
# 回滚（恢复老环境数据库）：
#   ssh ubuntu@3.124.149.172 'docker update --restart=always css-backend__db css-backend__ocr-db && docker start css-backend__db css-backend__ocr-db'
#
# 用法: SSH_KEY_PASSPHRASE=<口令> ASSUME_YES=1 ./停dev数据库.sh
#   口令: 默认从 SSH_KEY_PASSPHRASE 环境变量读；没有则交互式提示一次。
#   ASSUME_YES=1 跳过确认（无交互终端时必须）。
set -euo pipefail
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
set -a; . "$ENVF"; set +a
TGT="${DEV_USER:-ubuntu}@$DEV_HOST"
CTRS="css-backend__db css-backend__ocr-db"

if [ "${ASSUME_YES:-0}" != "1" ]; then
  read -r -p "将停止 $TGT 上的 $CTRS 并改 restart=unless-stopped，老环境业务将立即失能。输入 yes 继续: " ans
  [ "$ans" = "yes" ] || { echo "已取消"; exit 1; }
fi

# ---- ssh-agent：一次解锁全程复用（同 拉取三环境.sh 的原因：Windows ssh-agent 服务 Disabled）----
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

echo "== 停止前状态 =="
$SSH "$TGT" "docker ps -a --filter name=css-backend__db --filter name=css-backend__ocr-db --format '{{.Names}}|{{.Status}}|restart={{.Label \"com.docker.compose.project\"}}'"

echo "== docker stop -t 120（postgres 官方基底 SIGINT fast shutdown）=="
$SSH "$TGT" "docker stop -t 120 $CTRS"

echo "== 改 restart 策略 always→unless-stopped（防 daemon 重启复活；docker update 不重建容器）=="
$SSH "$TGT" "docker update --restart=unless-stopped $CTRS"

echo "== 停止后核验 =="
$SSH "$TGT" "for c in $CTRS; do
  st=\$(docker inspect -f '{{.State.Status}}' \$c)
  rp=\$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' \$c)
  echo \"\$c: state=\$st restart=\$rp\"
  [ \"\$st\" = exited ] || { echo \"[FATAL] \$c 未停止\"; exit 1; }
  [ \"\$rp\" = unless-stopped ] || { echo \"[FATAL] \$c 重启策略未改成 unless-stopped\"; exit 1; }
done
echo '数据卷原地保留（stop 不删卷）：'
docker inspect -f '{{range .Mounts}}{{.Name}} {{end}}' css-backend__db css-backend__ocr-db"

echo "===== 完成：两库容器已停止且不会随 daemon 重启复活 ====="
echo "回滚: ssh $TGT 'docker update --restart=always $CTRS && docker start $CTRS'"
