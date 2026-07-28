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
[ $# -ge 1 ] || { echo "至少一个环境: test|uat|prod"; exit 1; }

psql_run() { docker run --rm -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }

for env in "$@"; do
  case "$env" in test|uat|prod) ;; *) echo "跳过未知环境 $env"; continue;; esac
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
echo "===== 建库完成 ====="
echo "提醒: 环境变量里同步改 POSTGRES_DB=css-<env>-main、OCR_DATABASE_URL/OCR_ALEMBIC_DATABASE_URL 指向 css-<env>-ocr"
