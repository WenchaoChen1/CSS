#!/usr/bin/env bash
# 把库内 public schema 存量对象的 owner 从 master(postgres) 移交给低权应用角色 css_app_<env>。
#
# 为什么需要：库是用 pg_restore --no-owner -U postgres 恢复的，所有表 owner=postgres。
# GRANT ALL ON ALL TABLES 只给 DML（增删改查），而 ALTER TABLE / DROP TABLE / CREATE INDEX
# 【只认 owner 不认 GRANT】——不移交所有权，应用切到 css_app_<env> 后 alembic 迁移会报
# "must be owner of table xxx"。
#
# ⚠️ 绝不用 REASSIGN OWNED BY postgres：它会连 shared object（含其它数据库的 owner）一起改。
# 本脚本只逐对象 ALTER public schema 内的对象，范围可控。
#
# ⚠️ 每次跑 restore-dump-via-gw.sh / sync-db.sh（都以 postgres 身份 --no-owner 恢复）之后，
# owner 会被打回 postgres，必须重跑本脚本。
#
# 用法: ./reown-db-objects.sh <rds主机> <master密码> <test|uat|prod>
# 在能连通 RDS 的机器执行：优先用【原生 psql】（堡垒机 dnf 装过 postgresql16），
# 没有原生客户端时回退 docker postgres:16。所以它在堡垒机 / 应用机 / 装了 Docker 的本机都能跑。
# （2026-08-05 修：原来硬编码 docker run，在只有原生 psql 的堡垒机上直接报 docker not found。）
set -euo pipefail

HOST="${1:?用法: reown-db-objects.sh <rds主机> <master密码> <env>}"
PASS="${2:?缺 master 密码}"
ENV_NAME="${3:?缺环境: test|uat|prod}"
case "$ENV_NAME" in test|uat|prod) ;; *) echo "环境只能是 test|uat|prod"; exit 1 ;; esac

ROLE="css_app_${ENV_NAME}"
if command -v psql >/dev/null 2>&1; then
  PSQL() { PGPASSWORD="$PASS" psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
else
  PSQL() { docker run --rm -i -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -v ON_ERROR_STOP=1 "$@"; }
fi

# RDS 的 master(postgres) 不是真 superuser：改 owner / 改他人默认权限都要求先成为目标角色成员（幂等）
PSQL -d postgres -c "GRANT ${ROLE} TO postgres;"
# css_dev 是非生产共用的开发账号，prod 不建它——prod 环境跳过所有 css_dev 相关语句（2026-08-03 修）
HAS_DEV=0
if [ "$ENV_NAME" != "prod" ]; then
  HAS_DEV=1
  PSQL -d postgres -c "GRANT css_dev TO postgres;"
fi

for db in "css-${ENV_NAME}-main" "css-${ENV_NAME}-ocr"; do
  echo "===== 移交 $db 的 public schema 对象 owner → $ROLE ====="

  # 逐类对象生成并执行 ALTER ... OWNER TO（表/序列/视图/物化视图/类型&domain/函数&存储过程）
  PSQL -d "$db" <<SQL
DO \$do\$
DECLARE r record;
BEGIN
  -- schema 本身
  EXECUTE format('ALTER SCHEMA public OWNER TO %I', '${ROLE}');

  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO %I', r.tablename, '${ROLE}');
  END LOOP;

  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname='public' LOOP
    EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I', r.sequencename, '${ROLE}');
  END LOOP;

  FOR r IN SELECT viewname FROM pg_views WHERE schemaname='public' LOOP
    EXECUTE format('ALTER VIEW public.%I OWNER TO %I', r.viewname, '${ROLE}');
  END LOOP;

  FOR r IN SELECT matviewname FROM pg_matviews WHERE schemaname='public' LOOP
    EXECUTE format('ALTER MATERIALIZED VIEW public.%I OWNER TO %I', r.matviewname, '${ROLE}');
  END LOOP;

  -- 自定义类型与 domain（枚举很关键：alembic 会 ALTER TYPE ... ADD VALUE）
  FOR r IN
    SELECT t.typname FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname='public' AND (t.typtype IN ('e','d','c'))
      AND NOT EXISTS (SELECT 1 FROM pg_class c WHERE c.oid=t.typrelid AND c.relkind <> 'c')
  LOOP
    BEGIN
      EXECUTE format('ALTER TYPE public.%I OWNER TO %I', r.typname, '${ROLE}');
    EXCEPTION WHEN others THEN NULL; -- 表的隐式复合类型会报错，跳过
    END;
  END LOOP;

  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname='public'
  LOOP
    BEGIN
      EXECUTE format('ALTER ROUTINE %s OWNER TO %I', r.sig, '${ROLE}');
    EXCEPTION WHEN others THEN NULL; -- 扩展自带函数（如 pgvector）不可改，跳过
    END;
  END LOOP;
END
\$do\$;
SQL

  # 移交后：让 css_dev 仍能读写该角色将来新建的对象（默认权限按"建对象的角色"生效，故要为新 owner 声明）
  if [ "$HAS_DEV" = 1 ]; then
    PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES FOR ROLE ${ROLE} IN SCHEMA public GRANT ALL ON TABLES TO css_dev;"
    PSQL -d "$db" -c "ALTER DEFAULT PRIVILEGES FOR ROLE ${ROLE} IN SCHEMA public GRANT ALL ON SEQUENCES TO css_dev;"
    PSQL -d "$db" -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO css_dev;"
    PSQL -d "$db" -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO css_dev;"
  fi

  # 核对：public schema 内还有多少对象不属于新 owner
  echo -n "剩余非 ${ROLE} owner 的表数（应为 0）: "
  PSQL -d "$db" -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tableowner <> '${ROLE}'"
done

echo "===== 完成 ====="
echo "下一步：把 deploy-env/${ENV_NAME}/backend.env 的 POSTGRES_USER/POSTGRES_PASSWORD 与两个 OCR_*_URL"
echo "改成 ${ROLE}，再 put-params.sh ${ENV_NAME} + deploy-env.sh ${ENV_NAME} migrate + up。"
