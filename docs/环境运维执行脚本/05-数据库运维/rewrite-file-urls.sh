#!/usr/bin/env bash
# 把库中文件 URL 从【老账号 S3 桶域名】改写成【本环境新桶域名】（2026-08-04 新增）
#
# 背景：test/uat 库的数据来自老环境备份，其 file_url 存的是【永久直链】，指向老账号桶
#   `https://chain-serve-test.s3.amazonaws.com/...`（2026-08-04 实测 test 库 8 张表共 14313 行）。
#   老桶目前公开可读，所以图片/发票"看起来正常"——但这是一条隐形跨账号依赖：老账号一旦关公读/销户，
#   历史文件全部 404。本脚本把域名前缀换成本环境新桶，配合 老aws账号/migrate-s3-to-new.sh 搬文件。
#
# 设计（专为"临时迁移 → 20 天后彻底迁移"）：
#   · 幂等：WHERE 只命中老前缀，已改写过的行不匹配 → 重复跑零副作用
#   · 与文件同步【完全解耦】：可以先搬文件后改 URL，也可以只改不搬（反正老桶还公开）；
#     20 天后若【重新导入数据库】，URL 会变回老域名 —— 那时只需再跑一次本脚本
#   · 动态发现表：不硬编码表名，扫 information_schema 里所有 text/varchar 列 —— 将来数据库
#     结构变了（新表/新列存 URL）也不会漏（硬编码 8 张表是本脚本最容易埋坑的地方）
#   · 单事务：全部表一起提交，中途失败自动回滚
#   · 可回退：--revert 反向替换（新→老）
#
# 用法:
#   ./rewrite-file-urls.sh <test|uat|prod> [--dry-run] [--revert] [--old-base 前缀]
#     --dry-run    只统计每张表会改多少行，不写入（建议先跑）
#     --revert     反向：把新桶域名改回老桶域名（回滚用）
#     --old-base   老 URL 前缀（含无用的 key 路径段），默认
#                  https://chain-serve-test.s3.amazonaws.com/eu-central-1/files/
#                  —— 2026-08-04 决策"文件直落桶根"后，改写要连带去掉 `eu-central-1/files/` 这段：
#                  老 URL  https://chain-serve-test.s3.amazonaws.com/eu-central-1/files/<uuid>_<名>
#                  新 URL  https://s3.us-east-1.amazonaws.com/css-<env>-<账号>/<uuid>_<名>
#                  与 老aws账号/migrate-s3-to-new.sh 的 --strip-prefix 必须口径一致
# 前置: 目标机 SSM Online（本脚本经 ../09-远程执行与手动部署/run.sh 在机上跑 psql，RDS 仅内网可达）
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"; shift || true
case "$ENV_NAME" in test|uat|support-ref|prod) ;; *) echo "用法: $0 <test|uat|support-ref|prod> [--dry-run] [--revert] [--old-base 前缀]"; exit 1 ;; esac

DRY=0; REVERT=0; OLD_BASE="https://chain-serve-test.s3.amazonaws.com/eu-central-1/files/"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --revert) REVERT=1 ;;
    --old-base) OLD_BASE="$2"; shift ;;
    *) echo "[FAIL] 未知参数: $1"; exit 1 ;;
  esac
  shift
done

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
# 新前缀 = 代码拼 URL 的规则 {S3_ENDPOINT_URL}/{S3_STORAGE_BUCKET_NAME}/ + key（key 无前缀，文件直落桶根）
NEW_BASE="https://s3.us-east-1.amazonaws.com/css-${ENV_NAME}-${ACCOUNT_ID}/"

if [ "$REVERT" = 1 ]; then FROM="$NEW_BASE"; TO="$OLD_BASE"; else FROM="$OLD_BASE"; TO="$NEW_BASE"; fi

echo "===== 库内文件 URL 改写（$ENV_NAME）====="
echo "FROM: $FROM"
echo "TO:   $TO"
echo "$([ $DRY = 1 ] && echo '【DRY-RUN 只统计】' || echo '实际写入（单事务）')$([ $REVERT = 1 ] && echo '｜REVERT 反向' || true)"
[ "$ENV_NAME" = "prod" ] && [ "$DRY" = 0 ] && {
  printf '⚠️  目标是【生产库】，输入 prod 确认: '; read -r c
  [ "$c" = "prod" ] || { echo "已取消"; exit 1; }
}

# SQL 用 base64 传输，彻底避开 SSM/GBK/引号嵌套问题（历史教训：aws.exe 遇非 ASCII 会崩）
SQL=$(cat <<SQLEOF
\set ON_ERROR_STOP on
BEGIN;
DO \$do\$
DECLARE r record; n bigint; total bigint := 0;
BEGIN
  CREATE TEMP TABLE _rw(tbl text, col text, cnt bigint) ON COMMIT DROP;
  -- 动态发现：所有文本列里含 FROM 前缀的（不硬编码表名，避免结构变化后漏表）
  FOR r IN SELECT table_name, column_name FROM information_schema.columns
           WHERE table_schema = 'public' AND data_type IN ('text','character varying')
  LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE %I LIKE %L', r.table_name, r.column_name, '${FROM}%') INTO n;
    IF n > 0 THEN
      INSERT INTO _rw VALUES (r.table_name, r.column_name, n);
      total := total + n;
      IF ${DRY} = 0 THEN
        EXECUTE format('UPDATE %I SET %I = replace(%I, %L, %L) WHERE %I LIKE %L',
          r.table_name, r.column_name, r.column_name, '${FROM}', '${TO}', r.column_name, '${FROM}%');
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE '命中总行数: %', total;
END \$do\$;
SELECT tbl || '.' || col || ' -> ' || cnt || ' 行' FROM _rw ORDER BY cnt DESC;
$([ "$DRY" = 1 ] && echo 'ROLLBACK;' || echo 'COMMIT;')
-- 改写后残留核对：仍指向老前缀的行数（幂等验证，实际执行后应为 0）
SELECT 'residual_old_base=' || coalesce(sum(c), 0) FROM (
  SELECT count(*) c FROM file WHERE file_url LIKE '${OLD_BASE}%'
) t;
-- 另报仍指向老域名但【不在预期路径下】的行（若 >0 说明还有其它 key 前缀，需追加一次带 --old-base 的改写）
SELECT 'other_old_host_paths=' || count(*) FROM file
 WHERE file_url LIKE 'https://chain-serve-test.s3.amazonaws.com/%'
   AND file_url NOT LIKE '${OLD_BASE}%';
SQLEOF
)
B64=$(printf '%s' "$SQL" | base64 -w0)

bash ../09-远程执行与手动部署/run.sh "$ENV_NAME" "echo $B64 | base64 -d > /tmp/rw.sql; set -a; . /opt/css-cicd/env/$ENV_NAME/backend.env; set +a; docker run --rm -i --network css-$ENV_NAME-net postgres:16-alpine psql \"postgresql://\$POSTGRES_USER:\$POSTGRES_PASSWORD@\$POSTGRES_HOST:5432/\$POSTGRES_DB\" -v ON_ERROR_STOP=1 -f - < /tmp/rw.sql; rc=\$?; rm -f /tmp/rw.sql; exit \$rc"

echo
if [ "$DRY" = 1 ]; then
  echo "以上为预演（已 ROLLBACK）。确认无误后去掉 --dry-run 实际执行。"
else
  echo "[OK] 已提交。抽验：从上面任一表取一条 file_url 用 curl -I 看是否 200。"
  echo "     若文件还没搬到新桶，改写后会 404 —— 先跑 老aws账号/migrate-s3-to-new.sh $ENV_NAME"
fi
