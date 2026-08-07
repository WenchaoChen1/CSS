#!/usr/bin/env bash
# 在 RDS 实例上创建各环境的业务库（库名规范 2026-07-28 拍板）：
#   css-test-main / css-test-ocr / css-uat-main / css-uat-ocr（非生产实例）
#   css-prod-main / css-prod-ocr（生产实例）
# ocr 库自动加 pgvector 扩展。库名含连字符，SQL 内已用双引号处理；DSN 中可直接使用。
# ⚠️ RDS 在私有子网：本脚本需在 VPC 内机器（应用机/网关机经隧道）上执行，psql 通过 docker 提供。
# 用法: ./create-databases.sh <host> <master密码> <env...>   例: ./create-databases.sh xxx.rds.amazonaws.com 'pw' test uat
set -euo pipefail

HOST="${1:?用法: create-databases.sh <rds主机> <master密码> <env...>}"
PASS="${2:?缺 master 密码}"
shift 2
[ $# -ge 1 ] || { echo "至少一个环境: test|uat|support-ref|prod"; exit 1; }

# 优先原生 psql（堡垒机 dnf 装过 postgresql16），没有再回退 docker（与 reown-db-objects.sh 同款，2026-08-07）
if command -v psql >/dev/null 2>&1; then
  psql_run() { PGPASSWORD="$PASS" psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
else
  psql_run() { docker run --rm -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
fi

for env in "$@"; do
  case "$env" in test|uat|support-ref|prod) ;; *) echo "跳过未知环境 $env"; continue;; esac
  MAIN="css-$env-main"; OCR="css-$env-ocr"
  for db in "$MAIN" "$OCR"; do
    if psql_run -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1; then
      echo "库已存在: $db"
    else
      psql_run -d postgres -c "CREATE DATABASE \"$db\";"
      echo "库创建: $db"
    fi
  done
  psql_run -d "$OCR" -c "CREATE EXTENSION IF NOT EXISTS vector;"
  echo "pgvector 就绪: $OCR"
done

# 运维账号 css_ops 对【新建库】的访问校验（不做授权，只核对）：
# css_ops 是 rds_superuser 成员，对本实例的库天然有 CONNECT——**新建库自动覆盖，无需逐库授权**
# （2026-08-03 实测确认，机制说明见 create-db-accounts.sh 顶部注释）。这里只断言，防机制变化悄悄失效。
if psql_run -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='css_ops'" | grep -q 1; then
  BAD=$(psql_run -d postgres -tAc "SELECT count(*) FROM pg_database WHERE datname LIKE 'css%' AND NOT has_database_privilege('css_ops',datname,'CONNECT')" | tr -d '[:space:]')
  [ "${BAD:-1}" = "0" ] && echo "✅ css_ops 对新建库自动有权限（rds_superuser 继承，已校验）" \
    || { echo "[FATAL] $BAD 个库 css_ops 连不上——继承机制失效，见 create-db-accounts.sh 注释"; exit 1; }
else
  echo "提示: css_ops 角色尚未创建——跑 ./create-db-accounts.sh 建号（届时自动获得全部库权限）"
fi

echo "===== 建库完成 ====="
echo "提醒: 环境变量里同步改 POSTGRES_DB=css-<env>-main、OCR_DATABASE_URL/OCR_ALEMBIC_DATABASE_URL 指向 css-<env>-ocr"
