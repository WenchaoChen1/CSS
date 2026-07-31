#!/usr/bin/env bash
# 在 RDS 上创建【库级隔离】的 PostgreSQL 登录角色（低权应用账号 + dev + ops 超级账号）。
# 库名规范：css-<env>-main / css-<env>-ocr。角色与授权：
#   css_app_test  → 仅 css-test-main / css-test-ocr 读写（应用/运维）
#   css_app_uat   → 仅 css-uat-main  / css-uat-ocr  读写
#   css_dev       → 可建新库(CREATEDB)；test+uat 四库读写改数据；不能删 css-* 库（非 owner）——
#                   注意：PG 语义下它能删【自己新建的】库（owner 可删自有库），删不了 test/uat 存量库
#   css_ops       → rds_superuser（全库超级权限，人用；通过堡垒机隧道连）
#   （css_app_prod / prod 待 prod RDS 建成后另跑，见文末）
# 轮换：重跑本脚本即全员轮换（ALTER ROLE ... PASSWORD 重设并打印新值）；轮换后同步改 运维访问速查 与应用配置。
# 隔离手段：对每个库 REVOKE CONNECT FROM PUBLIC，再只 GRANT 给授权角色；master(postgres)是
# superuser 不受影响，现有以 postgres 连库的应用不受影响。
# ⚠️ 在 VPC 内机器（应用机/网关机隧道）上执行；psql 用 docker postgres:16 提供。
# 用法: ./create-db-accounts.sh <rds主机> <master密码> [test|uat|both]   默认 both
set -euo pipefail

HOST="${1:?用法: create-db-accounts.sh <rds主机> <master密码> [test|uat|both]}"
PASS="${2:?缺 master 密码}"
SCOPE="${3:-both}"

PSQL() { docker run --rm -i -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
gen() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20; }

grant_db() { # $1=db  $2...=授权角色
  local db="$1"; shift
  PSQL -d postgres -c "REVOKE CONNECT ON DATABASE \"$db\" FROM PUBLIC;"
  for r in "$@"; do
    PSQL -d postgres -c "GRANT CONNECT ON DATABASE \"$db\" TO $r;"
    PSQL -d "$db" -c "GRANT USAGE, CREATE ON SCHEMA public TO $r;"
    PSQL -d "$db" -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO $r;"
    PSQL -d "$db" -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $r;"
    PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $r;"
    PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $r;"
  done
}

ensure_role() { # $1=role  $2=password
  PSQL -d postgres <<SQL
DO \$do\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$1') THEN CREATE ROLE $1 LOGIN; END IF;
END \$do\$;
ALTER ROLE $1 LOGIN PASSWORD '$2';
SQL
}

declare -A PW
echo "===== 创建/更新库账号（scope=$SCOPE）====="

# ops：全库超级账号（人用）
PW[css_ops]=$(gen); ensure_role css_ops "${PW[css_ops]}"
PSQL -d postgres -c "GRANT rds_superuser TO css_ops;"

if [ "$SCOPE" = "test" ] || [ "$SCOPE" = "both" ]; then
  PW[css_app_test]=$(gen); ensure_role css_app_test "${PW[css_app_test]}"
  PW[css_dev]=$(gen);      ensure_role css_dev      "${PW[css_dev]}"
  PSQL -d postgres -c 'ALTER ROLE css_dev CREATEDB;'   # 允许建新库（其自建库归其所有、可自删；css-* 存量库非其所有、删不动）
  grant_db css-test-main css_app_test css_dev
  grant_db css-test-ocr  css_app_test css_dev
fi

if [ "$SCOPE" = "uat" ] || [ "$SCOPE" = "both" ]; then
  PW[css_app_uat]=$(gen); ensure_role css_app_uat "${PW[css_app_uat]}"
  grant_db css-uat-main css_app_uat css_dev
  grant_db css-uat-ocr  css_app_uat css_dev
fi

echo
echo "===== 生成的账号密码（请立刻抄进 运维访问速查.local.md，本输出不留存）====="
for r in "${!PW[@]}"; do printf '%-14s %s\n' "$r" "${PW[$r]}"; done
echo "master(postgres) 密码见 Secrets Manager（rds! 托管，90 天轮换）"
echo
echo "# prod：待 prod RDS 建成后执行 ——"
echo "#   ./create-db-accounts.sh <prod-rds主机> <prod-master密码> && 另建 css_app_prod（仅 css-prod-main/ocr）"
