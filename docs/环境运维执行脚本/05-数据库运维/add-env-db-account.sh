#!/usr/bin/env bash
# 为【单个】环境新建库级隔离的低权应用角色，不触碰任何已有角色的密码。
#
# 为什么单独一个脚本：create-db-accounts.sh 的语义是"重跑=全员轮换密码"（css_ops/css_dev/
# 全部 css_app_*），给已有实例【追加一个环境】时绝不能用它——会把 test/uat 应用的在用密码
# 一并轮换掉导致全环境掉线。本脚本只做增量：建 css_app_<env> + 授权到 css-<env>-main/ocr，
# 并给 css_dev 补上对新库的只读授权（角色须已存在，即 create-db-accounts.sh 已跑过的实例）。
#
# 角色名：PG 角色名不允许连字符，环境名里的 - 统一转 _（support-ref → css_app_support_ref）。
# 前置：库已由 create-databases.sh 建好。授权口径与 create-db-accounts.sh 完全一致。
# ⚠️ 在 VPC 内机器（应用机/网关机隧道)上执行；psql 用 docker postgres:16 提供。
# 用法: ./add-env-db-account.sh <rds主机> <master密码> <env>   例: ./add-env-db-account.sh xxx.rds.amazonaws.com 'pw' support-ref
set -euo pipefail

HOST="${1:?用法: add-env-db-account.sh <rds主机> <master密码> <env>}"
PASS="${2:?缺 master 密码}"
ENV_NAME="${3:?缺环境名，例: support-ref}"
case "$ENV_NAME" in
  test|uat) echo "[FATAL] $ENV_NAME 的账号由 create-db-accounts.sh 管理（含轮换语义），不要在这里重建"; exit 1 ;;
  prod) echo "[FATAL] prod 在独立 RDS 实例，走 create-db-accounts.sh 的 prod 流程"; exit 1 ;;
esac

ROLE="css_app_${ENV_NAME//-/_}"
MAIN="css-${ENV_NAME}-main"; OCR="css-${ENV_NAME}-ocr"

# 优先原生 psql（堡垒机 dnf 装过 postgresql16），没有再回退 docker（与 reown-db-objects.sh 同款）
if command -v psql >/dev/null 2>&1; then
  PSQL() { PGPASSWORD="$PASS" psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
else
  PSQL() { docker run --rm -i -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
fi
gen() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20; }

# 前置校验：两库须已存在；css_dev 应已存在（没有则跳过只读授权并提示）
for db in "$MAIN" "$OCR"; do
  PSQL -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1 \
    || { echo "[FATAL] 库不存在: $db —— 先跑 ./create-databases.sh $HOST '<master密码>' $ENV_NAME"; exit 1; }
done
HAS_DEV=$(PSQL -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='css_dev'" | tr -d '[:space:]')

# 建角色（已存在则只重设本角色密码——单环境轮换语义，影响面只有这一个角色）
PW=$(gen)
PSQL -d postgres <<SQL
DO \$do\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$ROLE') THEN CREATE ROLE $ROLE LOGIN; END IF;
END \$do\$;
ALTER ROLE $ROLE LOGIN PASSWORD '$PW';
SQL

# 库级隔离 + 读写授权（与 create-db-accounts.sh 的 grant_db 一致）
for db in "$MAIN" "$OCR"; do
  PSQL -d postgres -c "REVOKE CONNECT ON DATABASE \"$db\" FROM PUBLIC;"
  PSQL -d postgres -c "GRANT CONNECT ON DATABASE \"$db\" TO $ROLE;"
  PSQL -d "$db" -c "GRANT USAGE, CREATE ON SCHEMA public TO $ROLE;"
  PSQL -d "$db" -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO $ROLE;"
  PSQL -d "$db" -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $ROLE;"
  PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $ROLE;"
  PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $ROLE;"
  # css_dev 只读（与 grant_ro 一致）
  if [ "${HAS_DEV:-0}" = "1" ]; then
    PSQL -d postgres -c "GRANT CONNECT ON DATABASE \"$db\" TO css_dev;"
    PSQL -d "$db" -c "GRANT USAGE ON SCHEMA public TO css_dev;"
    PSQL -d "$db" -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO css_dev;"
    PSQL -d "$db" -c "GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO css_dev;"
    PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO css_dev;"
    PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO css_dev;"
  fi
done
[ "${HAS_DEV:-0}" = "1" ] || echo "提示: css_dev 角色不存在，跳过只读授权（该实例还没跑过 create-db-accounts.sh？）"

echo
echo "===== 新账号（请立刻抄进 运维访问速查.local.md / deploy-env/密码.local.md，本输出不留存）====="
printf '%-24s %s\n' "$ROLE" "$PW"
echo
echo "下一步："
echo "  1. 数据恢复/同步后跑 ./reown-db-objects.sh $HOST '<master密码>' $ENV_NAME 移交对象 owner"
echo "  2. deploy-env/$ENV_NAME/backend.env 的 POSTGRES_USER=$ROLE、POSTGRES_PASSWORD=上面的新密码，"
echo "     OCR_DATABASE_URL/OCR_ALEMBIC_DATABASE_URL 同步替换用户密码，再 put-params.sh $ENV_NAME"
