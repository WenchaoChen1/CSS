#!/usr/bin/env bash
# 查【老账号】021213872872 的 dev / stage / preprod 三台机器"最后一次部署是什么时候"。
# 纯只读（只跑 docker inspect / stat / uptime），符合"老账号是只读迁移源"的铁律。
#
# 为什么要一个脚本而不是随手 ssh 一条命令：**"部署时间"没有单一答案，四个时间戳含义完全不同**，
# 混用会得出错误结论（例如把"机器重启"当成"重新部署"）：
#
#   ① 容器 Created    ← **这个才是部署时间**。docker compose up 只在镜像或配置变了时重建容器，
#                        重建 = 那一刻做了一次真实部署。容器重启不会改它。
#   ② 容器 StartedAt  ← 最后一次"启动"。机器重启、restart:always 拉起都会刷新它，**不是部署**。
#   ③ 镜像 Created    ← 镜像被 GitLab CI **构建**的时间。可能远早于部署（构建完没立刻发）。
#   ④ 镜像 LastTagTime← 镜像被 pull 到这台机器的时间（docker 本地元数据）。接近部署但不等于部署
#                        （pull 了没 up 就不算）。
#
# 判读规则：以 ① 的最大值作为"最后一次部署"；若 ② 明显晚于 ① 且全体容器一致 → 那是机器重启，不是部署。
# 老账号由 GitLab CI 部署而我方无 GitLab 访问权，所以机上证据是唯一可得来源（GitLab Runner 的
# 构建目录 /builds/... 的 mtime 作为旁证一并采集——它反映最后一次 CI 作业落地）。
#
# 用法: ./查部署时间.sh [dev|stage|preprod|all]     # 默认 all
# 口令: 默认从 SSH_KEY_PASSPHRASE 环境变量读；没有则交互式提示一次（与 拉取三环境.sh 同机制）。
set -euo pipefail
export MSYS_NO_PATHCONV=1

TARGETS="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
set -a; . "$ENVF"; set +a

# ---- ssh-agent：一次解锁，全程复用（跑完自动 kill）----
# *_KEY 在 env 里是 Windows 路径，source 会吃掉 \U 之类的转义，所以原样 grep 再 cygpath 转换。
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

host_of() { case "$1" in dev) echo "${DEV_USER:-ubuntu}@$DEV_HOST";; stage) echo "${STAGE_USER:-ubuntu}@$STAGE_HOST";;
                         preprod) echo "${PREPROD_USER:-ubuntu}@$PREPROD_HOST";; *) return 1;; esac; }

# 远程只读采集脚本。注意：容器名可能含空格外的特殊字符，统一用 docker inspect 的 Go 模板一次输出，
# 避免逐容器 ssh 往返（三台 × 十几个容器会很慢）。
REMOTE='set -e
echo "### 机器"
echo "  当前时间(UTC): $(date -u "+%Y-%m-%d %H:%M:%S")"
echo "  开机至今: $(uptime -p 2>/dev/null || uptime)"
echo "  最后启动: $(uptime -s 2>/dev/null || echo 未知)"
echo "### 容器（Created=部署时间, StartedAt=最后启动）"
docker inspect $(docker ps -q) \
  --format "{{.Name}}|{{.Created}}|{{.State.StartedAt}}|{{.Config.Image}}|{{.State.Restarting}}|{{.RestartCount}}" 2>/dev/null \
  | sed "s|^/||" | sort -t"|" -k2 -r
echo "### 镜像（Created=CI 构建时间, LastTagTime=拉到本机的时间）"
for img in $(docker ps --format "{{.Image}}" | sort -u); do
  docker image inspect "$img" --format "{{.RepoTags}}|{{.Created}}|{{.Metadata.LastTagTime}}" 2>/dev/null || echo "$img|镜像已不在本地|"
done
echo "### GitLab Runner 构建目录（旁证：最后一次 CI 作业落地）"
for d in /builds /home/gitlab-runner/builds /var/lib/gitlab-runner; do
  [ -d "$d" ] && find "$d" -maxdepth 3 -type d -printf "%TY-%Tm-%Td %TH:%TM  %p\n" 2>/dev/null | sort -r | head -4
done
[ -d /builds ] || [ -d /home/gitlab-runner/builds ] || echo "  （无 Runner 构建目录——CI 可能在别处或用容器化 Runner）"
echo "### compose / 部署文件的最后修改时间（旁证）"
for f in /home/ubuntu/docker-compose*.y*ml /home/ubuntu/*/docker-compose*.y*ml /opt/*/docker-compose*.y*ml; do
  [ -f "$f" ] && stat -c "  %y  %n" "$f" 2>/dev/null
done | sort -r | head -6'

for env in dev stage preprod; do
  case "$TARGETS" in all|"$env") ;; *) continue ;; esac
  tgt="$(host_of "$env")" || { echo "[跳过] $env 未在 源环境.env 配置"; continue; }
  echo "================ $env（$tgt）================"
  # shellcheck disable=SC2029
  $SSH "$tgt" "$REMOTE" 2>&1 || echo "  [FAIL] $env 连不上或命令出错（dev/stage 若未开 SSH 见 装SSH公钥.sh）"
  echo
done

cat <<'TIP'
================ 怎么读这份输出 ================
· "最后一次部署" = 容器 Created 的**最大值**（容器被重建的那一刻）。
· 若所有容器的 StartedAt 挤在同一时刻、且明显晚于 Created → 那是**机器重启**，不是部署。
· 镜像 Created 比容器 Created 早很多 = 构建完放了一段时间才发布，属正常。
· RestartCount 大 = 该容器在反复崩溃重启，与部署时间无关但值得留意。
TIP
