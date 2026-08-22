#!/usr/bin/env bash
# 把 拉取三环境.sh 备份到 备份/数据库/<env>/ 的老账号三环境数据库 dump，
# 导入到【本机 Docker】的 Postgres 容器里，每环境两个库（库名含备份时间，2026-08-19 定）：
#   <env>_main_*.dump → 本地库 backup_<年月日时>_old_<env>_main （源库 postgres，业务主库）
#   <env>_ocr_*.dump  → 本地库 backup_<年月日时>_old_<env>_ocr  （源库 ocr_catalog，OCR 微服务库）
#   时间戳取自 dump 文件名（如 dev_main_20260819_151600.dump → backup_2026081915_old_dev_main），
#   与 RDS 留档库 backup_YYYYMMDD_* 命名惯例一致；同一小时重跑覆盖，不同时间并存。
#
# 说明：
#   - 默认目标容器 postgres-latest-5432（本机常驻 PG 18，restore PG16 的 custom dump 没有兼容问题；
#     可用 LOCAL_PG_CTR=<容器名> 覆盖）。⚠️ 不是 CSS 项目栈的 css-backend__db——本机当前没有该容器。
#   - 每个环境自动取目录里**时间戳最新**的一对 dump；也可用第二个参数指定时间戳（如 20260819_151600）。
#   - 同名本地库会先 DROP 再重建（带 FORCE 断开连接）——backup_*_old_* 库定位就是"快照镜像"，
#     同一小时的 dump 重跑即覆盖，不同时间的并存。
#   - pg_restore 加 --no-owner --no-privileges：源库的 owner/grant 在本地不存在，照单恢复只会刷错。
#     恢复后按"表数量 >0"校验成功，pg_restore 的扩展注释类警告不视为失败。
#
# 用法: ./导入本地数据库.sh [dev|stage|preprod|all] [main|ocr|all] [时间戳]
#   例: ./导入本地数据库.sh              # 三个环境 main+ocr 全导（默认，各取最新 dump）
#       ./导入本地数据库.sh dev          # 只导 dev 的两个库
#       ./导入本地数据库.sh all ocr      # 只导三环境的 OCR 库（配 LOCAL_PG_CTR 可导进别的容器）
#       ./导入本地数据库.sh all all 20260819_151600
set -euo pipefail
export MSYS_NO_PATHCONV=1

TARGETS="${1:-all}"; SCOPE="${2:-all}"; PIN_TS="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BAK="$ROOT/备份/数据库"
CTR="${LOCAL_PG_CTR:-postgres-latest-5432}"
PGUSER="${LOCAL_PG_USER:-postgres}"

docker inspect -f '{{.State.Status}}' "$CTR" 2>/dev/null | grep -q running \
  || { echo "[FATAL] 本地容器 $CTR 未运行（docker start $CTR，或 LOCAL_PG_CTR 指定其它容器）"; exit 1; }

latest_dump() { # $1=env $2=tag(main|ocr) → 输出最新（或 PIN_TS 指定）的 dump 路径
  local env="$1" tag="$2" f
  if [ -n "$PIN_TS" ]; then
    f="$BAK/$env/${env}_${tag}_${PIN_TS}.dump"
    [ -f "$f" ] || { echo ""; return; }
  else
    f="$(ls -1 "$BAK/$env/${env}_${tag}_"*.dump 2>/dev/null | sort | tail -1)"
  fi
  echo "$f"
}

restore_one() { # $1=env $2=tag $3=dump路径 → 恢复到本地库 backup_<年月日时>_old_<env>_<tag>
  local env="$1" tag="$2" dump="$3"
  # 从 dump 文件名提取时间戳（<env>_<tag>_YYYYMMDD_HHMMSS.dump → YYYYMMDDHH）
  local ts10
  ts10="$(basename "$dump" .dump | sed -E 's/.*_([0-9]{8})_([0-9]{2})[0-9]{4}$/\1\2/')"
  [[ "$ts10" =~ ^[0-9]{10}$ ]] || { echo "[$env] ❌ 无法从 $(basename "$dump") 提取时间戳"; return 1; }
  local db="backup_${ts10}_old_${env}_${tag}"
  head -c5 "$dump" | grep -q PGDMP || { echo "[$env] ❌ $dump 不是 pg_dump custom 格式"; return 1; }
  echo "[$env] $(basename "$dump") → 本地库 $db"
  docker exec "$CTR" psql -U "$PGUSER" -q -c "DROP DATABASE IF EXISTS \"$db\" WITH (FORCE)" \
    -c "CREATE DATABASE \"$db\""
  # -i 经 stdin 送入容器内 pg_restore，不在容器里落盘；警告（owner/扩展注释类）不中断
  local warn=0
  docker exec -i "$CTR" pg_restore -U "$PGUSER" --no-owner --no-privileges -d "$db" < "$dump" || warn=$?
  local tables
  tables="$(docker exec "$CTR" psql -U "$PGUSER" -d "$db" -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname='public'")"
  [ "${tables:-0}" -gt 0 ] || { echo "[$env] ❌ $db 恢复后 public 无表，视为失败"; return 1; }
  local size
  size="$(docker exec "$CTR" psql -U "$PGUSER" -tAc "SELECT pg_size_pretty(pg_database_size('$db'))")"
  if [ "$warn" -ne 0 ]; then
    echo "[$env] ✅ $db  表 $tables 张 / $size（pg_restore 有非致命警告，exit=$warn，已按表数校验通过）"
  else
    echo "[$env] ✅ $db  表 $tables 张 / $size"
  fi
}

import_env() {
  local env="$1" tag f
  for tag in $TAGS; do
    f="$(latest_dump "$env" "$tag")"
    [ -n "$f" ] || { echo "[$env] ❌ 备份/数据库/$env/ 缺 $tag 的 dump（先跑 拉取三环境.sh $env db）"; return 1; }
    restore_one "$env" "$tag" "$f"
  done
}

case "$TARGETS" in all) LIST="dev stage preprod";; dev|stage|preprod) LIST="$TARGETS";;
  *) echo "第一个参数只能是 dev|stage|preprod|all"; exit 1;; esac
case "$SCOPE" in all) TAGS="main ocr";; main|ocr) TAGS="$SCOPE";;
  *) echo "第二个参数只能是 main|ocr|all"; exit 1;; esac
echo "目标容器: $CTR ($(docker exec "$CTR" psql -U "$PGUSER" -tAc 'SHOW server_version'))"
for e in $LIST; do echo "========== $e =========="; import_env "$e"; echo; done

echo "===== 完成 ====="
docker exec "$CTR" psql -U "$PGUSER" -tAc \
  "SELECT datname || '  ' || pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datname LIKE 'backup\\_%' ORDER BY 1"
HOST_PORT="$(docker port "$CTR" 5432/tcp 2>/dev/null | head -1 | sed 's/.*://')"
echo "连接: localhost:${HOST_PORT:-?}  用户 $PGUSER（容器 $CTR）"
