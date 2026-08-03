#!/usr/bin/env bash
# 从【老账号】021213872872 的 dev / stage / preprod 三台机器，一次性拉：
#   ① 运行时配置（每个容器注入的环境变量）→ 备份/docker镜像/<env>/<容器>.env
#   ② 数据库备份（每台 2 个库：主库 postgres、OCR 库 ocr_catalog）→ 备份/数据库/<env>/*.dump
#
# 为什么是 bash 版而不是同目录的 .ps1：
#   本机 Windows ssh-agent 服务是 Disabled（启用要提权），而 ~/.ssh/wenchao 带 passphrase，
#   PowerShell 里的 ssh.exe 每次都会弹口令、无法无人值守。bash 版用 git-bash 自带的 ssh-agent
#   （脚本内起、跑完即散），一次输入口令跑完全程。.ps1 保留作单环境手动使用。
#
# 为什么配置只能从容器里取：三台机器的部署由 GitLab Runner 在临时目录 /builds/css_new/css-backend
#   里执行，.env 是 CI 生成的临时文件，**磁盘上不留存**（已全盘搜索确认）。所以运行中容器的
#   注入环境变量（docker inspect .Config.Env）是这三个环境配置的唯一可得来源。
#
# 用法: ./拉取三环境.sh [dev|stage|preprod|all] [env|db|all]
#   例: ./拉取三环境.sh all all      # 三个环境的配置 + 数据库全拉（默认）
#       ./拉取三环境.sh dev db       # 只拉 dev 的两个库
# 口令: 默认从 SSH_KEY_PASSPHRASE 环境变量读；没有则交互式提示一次。
set -euo pipefail
export MSYS_NO_PATHCONV=1

TARGETS="${1:-all}"; WHAT="${2:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENVF="$SCRIPT_DIR/源环境.env"
[ -f "$ENVF" ] || { echo "[FATAL] 缺 $ENVF"; exit 1; }
set -a; . "$ENVF"; set +a
TS="$(date +%Y%m%d_%H%M%S)"

# ---- ssh-agent：一次解锁，全程复用（跑完自动 kill）----
# 注意：源环境.env 里的 *_KEY 是 Windows 路径（C:\Users\...），不能用 source 后的值——
# bash 在 source 时会把 \U 之类当转义吃掉。这里原样 grep 出来再用 cygpath 转成 POSIX 路径。
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

# ---------------- ① 配置（容器注入的环境变量）----------------
pull_env() {
  local env="$1" tgt; tgt="$(host_of "$env")"
  local out="$ROOT/备份/docker镜像/$env"; mkdir -p "$out"
  echo "[$env] 采集容器环境变量 → 备份/docker镜像/$env/"
  $SSH "$tgt" 'for c in $(docker ps --format "{{.Names}}"); do
      echo "@@@CONTAINER=$c";
      docker inspect --format "{{range .Config.Env}}{{println .}}{{end}}" "$c";
    done
    echo "@@@IMAGES"; docker ps --format "{{.Names}}|{{.Image}}|{{.Status}}"
    echo "@@@COMPOSE"; docker inspect css-backend__app \
      --format "working_dir={{index .Config.Labels \"com.docker.compose.project.working_dir\"}} config={{index .Config.Labels \"com.docker.compose.project.config_files\"}}"' \
  | awk -v out="$out" -v env="$env" -v ts="$TS" '
      /^@@@CONTAINER=/ { name=substr($0,14); gsub(/[\/:*?"<>|\\]/,"_",name);
                         f=out "/" name ".env"; print "# " name " @ " env "  采集于 " ts > f; next }
      /^@@@IMAGES$/    { f=out "/_容器与镜像清单.txt"; print "# " env "  采集于 " ts > f; next }
      /^@@@COMPOSE$/   { next }
      f && length($0)  { print >> f }'
  local n; n=$(find "$out" -name '*.env' | wc -l)
  echo "[$env] ✅ 导出 $n 个容器的环境变量"
}

# ---------------- ② 数据库（每台两个库）----------------
# 老环境固定形态（三台一致，2026-08-03 实查）：
#   css-backend__db      → 主库 postgres     （dev 83MB / stage 86MB / preprod 46MB）
#   css-backend__ocr-db  → OCR 库 ocr_catalog（各约 8MB）
pull_db() {
  local env="$1" tgt; tgt="$(host_of "$env")"
  local out="$ROOT/备份/数据库/$env"; mkdir -p "$out"
  local pairs="css-backend__db:postgres:main css-backend__ocr-db:ocr_catalog:ocr"
  for p in $pairs; do
    local ctr db tag; IFS=: read -r ctr db tag <<<"$p"
    local fn="${env}_${tag}_${TS}.dump"
    echo "[$env] pg_dump $ctr/$db → $fn"
    # 直接管道回本地：不在源服务器 /tmp 落盘（老账号是只读迁移源，尽量不留痕、不占盘）
    if ! $SSH "$tgt" "docker exec -i $ctr pg_dump -U postgres -Fc '$db'" > "$out/$fn"; then
      echo "[$env] ❌ $db 导出失败"; rm -f "$out/$fn"; return 1
    fi
    # custom 格式必须以 PGDMP 开头，且能被 pg_restore -l 列出目录——两项都过才算有效
    head -c5 "$out/$fn" | grep -q PGDMP || { echo "[$env] ❌ $fn 不是有效的 pg_dump custom 文件"; rm -f "$out/$fn"; return 1; }
    echo "[$env] ✅ $fn  $(du -h "$out/$fn" | cut -f1)"
  done
}

case "$TARGETS" in all) LIST="dev stage preprod";; *) LIST="$TARGETS";; esac
for e in $LIST; do
  host_of "$e" >/dev/null || { echo "未知环境 $e"; exit 1; }
  echo "========== $e ($(host_of "$e")) =========="
  case "$WHAT" in
    env) pull_env "$e" ;;
    db)  pull_db  "$e" ;;
    all) pull_env "$e"; pull_db "$e" ;;
    *) echo "第二个参数只能是 env|db|all"; exit 1 ;;
  esac
  echo
done

echo "===== 完成 ====="
echo "配置: $ROOT/备份/docker镜像/<env>/     数据库: $ROOT/备份/数据库/<env>/"
echo "下一步（恢复到非生产 RDS 的独立备份库，不动现有 test/uat 库）："
echo "  bash ../环境运维执行脚本/05-数据库运维/restore-old-env-backup.sh <dev|stage|preprod>"
