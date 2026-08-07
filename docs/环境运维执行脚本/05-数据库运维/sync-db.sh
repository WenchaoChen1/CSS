#!/usr/bin/env bash
# 把源库数据同步到目标库（pg_dump -Fc 流式 → pg_restore，经 docker 提供客户端，机器无需装 pg 工具）。
# 典型用途：
#   旧 RDS css-non-prod 的 css_test  → 新实例 css-non-prod 的 css-test-main
#   旧 RDS css-non-prod 的 ocr_test  → 新实例的 css-test-ocr
#   test 数据 → uat 库（css-uat-main / css-uat-ocr）作为验收基线
# ⚠️ 目标库会先被 --clean 清空同名对象；生产同步前先打快照。需在能同时连通两端的机器上执行（VPC 内）。
# 用法: ./sync-db.sh '<源DSN>' '<目标DSN>'
#   DSN 例: postgresql://postgres:PASS@old-host:5432/css_test
#           postgresql://postgres:PASS@new-host:5432/css-test-main
set -euo pipefail

SRC="${1:?用法: sync-db.sh <源DSN> <目标DSN>}"
DST="${2:?缺目标 DSN}"

echo "同步: ${SRC%%\?*}"
echo "  →   ${DST%%\?*}"

# 优先原生客户端（堡垒机 dnf 装过 postgresql16，无 docker），没有再回退 docker（2026-08-07）
if command -v pg_dump >/dev/null 2>&1 && command -v pg_restore >/dev/null 2>&1; then
  pg_dump --format=custom --no-owner --no-privileges "$SRC" \
    | pg_restore --no-owner --no-privileges --clean --if-exists --dbname "$DST"
else
  docker run --rm postgres:16 pg_dump --format=custom --no-owner --no-privileges "$SRC" \
    | docker run --rm -i postgres:16 pg_restore --no-owner --no-privileges --clean --if-exists \
        --dbname "$DST"
fi

echo "===== 同步完成 ====="
echo "核对: 目标库表数/行数抽查；alembic_version 是否与代码迁移链一致（不一致勿跑 upgrade）"
