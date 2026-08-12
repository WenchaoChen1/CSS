#!/usr/bin/env bash
# 给【某个环境的两个业务库】追加一个【只读】登录角色（缺省 css_dev），不触碰任何既有角色的密码。
#
# 为什么单独一个脚本（三者语义各不相同，别用错）：
#   · create-db-accounts.sh  = 建全套账号，重跑 = 全员轮换密码（在 prod 上重跑会把 css_app_prod 的
#                              在用密码换掉 → 应用当场掉线）；其 prod 分支刻意不建 css_dev。
#   · add-env-db-account.sh  = 给非生产实例追加一个环境的【读写】应用角色（prod 显式拒绝）。
#   · 本脚本                 = 纯增量追加【只读】角色，幂等、不轮换、支持 prod。
#
# 2026-08-10 用户拍板：prod 也要一个 css_dev 只读账号（推翻 2026-08-03「生产实例不设开发者只读账号」
# 的口径）——用于查生产数据，只能看不能改。
#
# ⚠️ 关键技术点（踩过的坑，勿删）：两库的表 owner 已由 reown-db-objects.sh 移交给 css_app_<env>，
#    所以【未来】alembic 迁移新建的表，其默认权限必须挂在 **owner 名下**才生效——
#    只写 `ALTER DEFAULT PRIVILEGES IN SCHEMA public ...`（等价于 FOR ROLE postgres）对新表无效，
#    必须同时下 `ALTER DEFAULT PRIVILEGES FOR ROLE css_app_<env> ...`（见 make-css-dev-readonly.sh 同款处理）。
#    否则现象是：今天验证全通过，下次上线加了新表后 css_dev 看不到那张表。
#
# 只读的含义：CONNECT + USAGE(schema) + SELECT(表/序列)；显式 REVOKE 掉写权限与 CREATE；
#            角色本身 NOCREATEDB / NOCREATEROLE / NOSUPERUSER。
#
# ⚠️ 在 VPC 内机器（堡垒机/应用机）上执行——RDS 在私有子网，本机不可达。
#    prod 用法示例（在 css-prod-bastion 上，master 密码现取 Secrets Manager 的 rds! secret）：
#      ./add-readonly-db-account.sh <prod-rds主机> '<master密码>' prod
# 用法: ./add-readonly-db-account.sh <rds主机> <master密码> <test|uat|support-ref|support-demo|support-sync|prod> [角色名=css_dev] [--rotate]
#   --rotate：角色已存在时也重设密码（缺省不动既有密码，只补授权）
set -euo pipefail

HOST="${1:?用法: add-readonly-db-account.sh <rds主机> <master密码> <env> [角色名=css_dev] [--rotate]}"
PASS="${2:?缺 master 密码}"
ENV_NAME="${3:?缺环境名: test|uat|support-ref|support-demo|support-sync|prod}"
shift 3
ROLE="css_dev"; ROTATE=0
for arg in "$@"; do
  case "$arg" in
    --rotate) ROTATE=1 ;;
    *) ROLE="$arg" ;;
  esac
done
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "[FATAL] 环境必须是 test|uat|support-ref|support-demo|support-sync|prod（收到: $ENV_NAME）"; exit 1 ;; esac
# PG 角色名不允许连字符
case "$ROLE" in *-*) echo "[FATAL] 角色名不能含连字符: $ROLE"; exit 1 ;; esac

if [ "$ENV_NAME" = "prod" ]; then
  echo "⚠️ 目标是【生产实例】：将为 css-prod-main / css-prod-ocr 追加只读角色 $ROLE（不动任何既有账号）。"
  printf '确认请输入 prod: '
  read -r CONFIRM
  [ "$CONFIRM" = "prod" ] || { echo "已取消"; exit 1; }
fi

APP_ROLE="css_app_${ENV_NAME//-/_}"
MAIN="css-${ENV_NAME}-main"; OCR="css-${ENV_NAME}-ocr"

# 优先原生 psql（堡垒机 dnf 装过 postgresql16），没有再回退 docker（与本目录其它脚本同款）
if command -v psql >/dev/null 2>&1; then
  PSQL() { PGPASSWORD="$PASS" psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
else
  PSQL() { docker run --rm -i -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
fi
gen() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20; }

# 前置校验：两库须已存在
for db in "$MAIN" "$OCR"; do
  PSQL -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1 \
    || { echo "[FATAL] 库不存在: $db —— 先跑 ./create-databases.sh $HOST '<master密码>' $ENV_NAME"; exit 1; }
done

EXISTS=$(PSQL -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ROLE'" | tr -d '[:space:]')
NEWPW=""
if [ "${EXISTS:-0}" != "1" ] || [ "$ROTATE" = "1" ]; then
  NEWPW=$(gen)
  PSQL -d postgres <<SQL
DO \$do\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='$ROLE') THEN CREATE ROLE $ROLE LOGIN; END IF;
END \$do\$;
ALTER ROLE $ROLE LOGIN PASSWORD '$NEWPW';
SQL
else
  echo "角色 $ROLE 已存在，保留现有密码（要换密码加 --rotate 或用 change-db-password.sh）"
fi
# 只读角色的硬约束
# ⚠️ 不能带 NOSUPERUSER：RDS 的 master(postgres) 自身不是真 superuser，改这个属性会报
#    "permission denied to alter role / Only roles with the SUPERUSER attribute may change it"（2026-08-10 实测）。
#    新建角色本来就非 superuser，下面的验证会断言 rolsuper=f。
PSQL -d postgres -c "ALTER ROLE $ROLE NOCREATEDB NOCREATEROLE;"

for db in "$MAIN" "$OCR"; do
  echo "===== 授权只读: $db → $ROLE ====="
  PSQL -d postgres -c "GRANT CONNECT ON DATABASE \"$db\" TO $ROLE;"
  PSQL -d "$db" >/dev/null <<SQL
-- 先撤干净再给，确保是纯只读（幂等；角色若曾有写权限也会被收回）
REVOKE CREATE ON SCHEMA public FROM $ROLE;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM $ROLE;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM $ROLE;
GRANT USAGE ON SCHEMA public TO $ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $ROLE;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO $ROLE;
-- 未来 postgres 建的对象
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM $ROLE;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM $ROLE;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO $ROLE;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON SEQUENCES TO $ROLE;
-- 未来 owner（$APP_ROLE，alembic 迁移就是以它建表）建的对象 —— 缺这段则新表看不到
ALTER DEFAULT PRIVILEGES FOR ROLE $APP_ROLE IN SCHEMA public REVOKE ALL ON TABLES FROM $ROLE;
ALTER DEFAULT PRIVILEGES FOR ROLE $APP_ROLE IN SCHEMA public REVOKE ALL ON SEQUENCES FROM $ROLE;
ALTER DEFAULT PRIVILEGES FOR ROLE $APP_ROLE IN SCHEMA public GRANT SELECT ON TABLES TO $ROLE;
ALTER DEFAULT PRIVILEGES FOR ROLE $APP_ROLE IN SCHEMA public GRANT SELECT ON SEQUENCES TO $ROLE;
SQL
done

echo
echo "--- 验证（每库：可SELECT 应等于表数、可INSERT 必须为 0）---"
FAIL=0
ISDB=$(PSQL -d postgres -tAc "select rolcreatedb from pg_roles where rolname='$ROLE'" | tr -d '[:space:]')
ISSU=$(PSQL -d postgres -tAc "select rolsuper from pg_roles where rolname='$ROLE'" | tr -d '[:space:]')
echo "$ROLE: CREATEDB=$ISDB（应为 f）, SUPERUSER=$ISSU（应为 f）"
{ [ "$ISDB" = "f" ] && [ "$ISSU" = "f" ]; } || FAIL=1
for db in "$MAIN" "$OCR"; do
  T=$(PSQL -d "$db" -tAc "select count(*) from information_schema.tables where table_schema='public'" | tr -d '[:space:]')
  S=$(PSQL -d "$db" -tAc "select count(*) from information_schema.tables where table_schema='public' and has_table_privilege('$ROLE', quote_ident(table_schema)||'.'||quote_ident(table_name), 'SELECT')" | tr -d '[:space:]')
  W=$(PSQL -d "$db" -tAc "select count(*) from information_schema.tables where table_schema='public' and has_table_privilege('$ROLE', quote_ident(table_schema)||'.'||quote_ident(table_name), 'INSERT')" | tr -d '[:space:]')
  echo "$db: 表 $T | 可SELECT $S | 可INSERT $W"
  [ "$W" = "0" ] || FAIL=1
  [ "$S" = "$T" ] || FAIL=1
done
[ "$FAIL" = "0" ] || { echo "[FATAL] 未收敛到只读（可INSERT>0 或有表 SELECT 不到），见上"; exit 1; }
echo "✅ $ROLE 对 $MAIN / $OCR 已是纯只读（含未来新表：默认权限已挂 $APP_ROLE 名下）"

if [ -n "$NEWPW" ]; then
  echo
  echo "===== 新账号密码（只打印这一次，请立刻抄进 deploy-env/密码.local.md）====="
  printf '%-14s %s\n' "$ROLE" "$NEWPW"
  echo "连接（隧道开在 5433 时）: psql \"postgresql://$ROLE:<密码>@localhost:5433/$MAIN\""
  echo "隧道: docs/环境运维执行脚本/05-数据库运维/db-tunnel.sh $ENV_NAME"
fi
