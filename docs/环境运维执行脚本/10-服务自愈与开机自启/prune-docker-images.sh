#!/usr/bin/env bash
# 清理应用机上堆积的旧版本 docker 镜像（保留最近 N 个版本 + 正在运行的）。
#
# 为什么需要（2026-08-05 事故）：test 机 50GB 盘用到 98%，docker 镜像占 45.9GB / 89 个（仅 11 个在用），
# CI 的 migrate 直接失败在 `no space left on device`。
# 根因：deploy.sh 收尾只跑 `docker image prune -f`——那**只删悬空镜像（<none> 无 tag 的）**，
# 而 CI 每次部署产生的是【带 tag】的版本镜像（<env>-v25、v26…），prune 完全不碰，于是无限堆积。
# ECR 侧有 lifecycle 保 5 个，但那管的是仓库，跟机器上已拉下来的镜像无关——这是两件事，容易混。
#
# 策略：
#   · 正在被容器使用的镜像绝不删（docker 本身会拒绝，这里再显式排除一层）
#   · 每个仓库按 tag 里的版本号 vN 倒序，保留最近 KEEP 个
#   · 同时清悬空镜像与构建缓存
#   · 公共镜像（redis/kafka/rabbitmq 等，无 <env>-vN 形态的 tag）只在悬空时清，不按版本删
#
# 用法:
#   ./prune-docker-images.sh <test|uat|support-ref|support-demo|prod> [保留版本数]        # 预演，默认保留 3
#   ./prune-docker-images.sh <test|uat|support-ref|support-demo|prod> [保留版本数] --yes  # 实际删除
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|prod) ;; *) echo "用法: $0 <test|uat|support-ref|support-demo|prod> [保留版本数] [--yes]"; exit 1 ;; esac
KEEP="${2:-3}"; [ "$KEEP" = "--yes" ] && KEEP=3
GO=0
for a in "$@"; do [ "$a" = "--yes" ] && GO=1; done

echo "===== 清理 $ENV_NAME 应用机的旧镜像（保留最近 $KEEP 个版本）====="
echo "$([ "$GO" = 1 ] && echo '【实际删除】' || echo '【预演，不删】')"

# 远程脚本：$KEEP/$GO 由本地插值，其余变量在远端展开
REMOTE='set -e
echo "--- 清理前:"
df -h / | tail -1
docker system df | grep -E "^Images|^Build"

RUNNING=$(docker ps --format "{{.Image}}" | sort -u)
echo "--- 正在使用的镜像 $(echo "$RUNNING" | wc -l) 个（绝不删）"

# 逐仓库挑出"带 <env>-vN tag 且不在运行中"的镜像，按版本号倒序留 KEEP 个
TO_DEL=""
for repo in $(docker images --format "{{.Repository}}" | grep -E "/(css-backend|css-frontend)/" | sort -u); do
  TAGS=$(docker images --format "{{.Tag}}" "$repo" | grep -E "^[a-z][a-z0-9-]*-v[0-9]+$" | sort -Vr || true)
  [ -n "$TAGS" ] || continue
  N=0
  for t in $TAGS; do
    N=$((N+1))
    IMG="$repo:$t"
    if [ "$N" -le '"$KEEP"' ]; then continue; fi
    echo "$RUNNING" | grep -qx "$IMG" && { echo "  [跳过-在用] $IMG"; continue; }
    TO_DEL="$TO_DEL $IMG"
  done
done

CNT=$(echo $TO_DEL | wc -w)
echo "--- 待删版本镜像: $CNT 个"
for i in $TO_DEL; do echo "    $i"; done | head -20
[ "$CNT" -gt 20 ] && echo "    …（共 $CNT 个）"

if [ '"$GO"' != 1 ]; then
  echo "--- 预演结束，未删除"
  exit 0
fi

for i in $TO_DEL; do docker rmi "$i" >/dev/null 2>&1 && echo "  [OK] 删除 $i" || echo "  [跳过] $i（被引用或已不存在）"; done
echo "--- 清悬空镜像与构建缓存:"
docker image prune -f | tail -1
docker builder prune -f 2>/dev/null | tail -1 || true
echo "--- 清理后:"
df -h / | tail -1
docker system df | grep -E "^Images|^Build"'

bash ../09-远程执行与手动部署/run.sh "$ENV_NAME" "$REMOTE"

echo
if [ "$GO" != 1 ]; then
  echo "确认无误后加 --yes 实际执行"
else
  echo "[OK] 完成。建议把本脚本挂进部署流程或定时任务，避免再次撑满："
  echo "     deploy.sh 收尾的 docker image prune 只删悬空镜像，带 tag 的旧版本要靠本脚本清。"
fi
