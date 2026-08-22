#!/usr/bin/env bash
# 非生产环境数据脱敏（从生产/preprod 导入真实数据后【必须】执行一次）：
#   1) 所有 email 类文本列  → 值前面加 "1"（1foo@bar.com，发不出去也认不出人）
#   2) 所有 phone 类文本列  → 值后面加 "1"（打不通）
#   3) 所有 password_hash   → 统一为口令 Test1234! 的哈希
#      （算法取自目标环境 env：pbkdf2_hmac(PASSWORD_HASH_ALGORITHM, pwd, PASSWORD_SALT, PASSWORD_HASH_ITERATIONS)，
#       盐值必须与运行环境一致，否则改完仍然登录不上——历史踩过这个坑）
# 列是动态遍历 information_schema 找的（只认 text/varchar/char），并排除列名含 type 的枚举类字段。
# 在应用机上经 SSM 执行（它在 VPC 内、能连 RDS）。
# prod：仅允许 --emails-phones-only 模式（2026-08-07 用户拍板：prod 数据源自 preprod，要求邮箱前加 1、
#       手机号后加 1，但【不动口令哈希】——保留 preprod 原口令 + 原 PASSWORD_SALT，用户仍可原口令登录），
#       且须手输 prod 二次确认。整库口令统一（默认模式）在 prod 永远拒绝。
# 用法: ./anonymize-db.sh <test|uat|support-ref|support-demo|support-sync> [口令，默认 Test1234!] [--emails-phones-only]
#       ./anonymize-db.sh prod --emails-phones-only
#       ./anonymize-db.sh uat --emails-phones-only --skip-email-prefix swp
#         （--skip-email-prefix P：email 以 P 开头（不区分大小写）的行不加前缀 1——用于保留自有团队邮箱可收信。
#          注意：之后如再跑 mask-residual-pii.sh，它会把这些未加 1 的邮箱当残留替换掉，须跳过或给它加同样排除。）
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: anonymize-db.sh <test|uat|support-ref|support-demo|support-sync|prod> [口令] [--emails-phones-only] [--skip-email-prefix P]}"
shift || true
NEW_PASSWORD="Test1234!"
PII_ONLY=0
SKIP_EMAIL_PREFIX=""
while [ $# -gt 0 ]; do
  case "$1" in
    --emails-phones-only) PII_ONLY=1 ;;
    --skip-email-prefix)
      shift
      SKIP_EMAIL_PREFIX="${1:?--skip-email-prefix 需要一个前缀值}"
      # 前缀会拼进 SQL 字面量，只放行安全字符，防注入
      case "$SKIP_EMAIL_PREFIX" in
        *[!A-Za-z0-9_.@+-]*) echo "--skip-email-prefix 只允许字母数字与 _ . @ + -"; exit 1 ;;
      esac ;;
    *) NEW_PASSWORD="$1" ;;
  esac
  shift || true
done
REGION="us-east-1"
case "$ENV_NAME" in
  test|uat|support-ref|support-demo|support-sync) ;;
  prod)
    if [ "$PII_ONLY" != "1" ]; then
      echo "拒绝：prod 只允许 --emails-phones-only 模式（只加邮箱前缀/手机号后缀，不改任何口令）"; exit 1
    fi
    echo "⚠️ 即将对【生产库】做邮箱/手机号脱敏（email 前加 1、phone 后加 1；不动口令）。"
    printf '确认请输入 prod: '
    read -r CONFIRM
    [ "$CONFIRM" = "prod" ] || { echo "已取消"; exit 1; }
    ;;
  *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../../../deploy-env/$ENV_NAME/backend.env"
[ -f "$ENV_FILE" ] || { echo "缺 $ENV_FILE"; exit 1; }
getvar() { { grep -E "^$1=" "$ENV_FILE" || true; } | tail -1 | cut -d= -f2- | tr -d '"\r'; }

ALGO="$(getvar PASSWORD_HASH_ALGORITHM)"; ALGO="${ALGO:-sha256}"
SALT="$(getvar PASSWORD_SALT)"
ITER="$(getvar PASSWORD_HASH_ITERATIONS)"; ITER="${ITER:-100000}"
DB="$(getvar POSTGRES_DB)"

HASH_HEX=""
if [ "$PII_ONLY" = "1" ]; then
  echo "目标: $ENV_NAME / 库 $DB（--emails-phones-only：不改口令哈希）"
else
  [ -n "$SALT" ] || { echo "$ENV_FILE 缺 PASSWORD_SALT"; exit 1; }
  # ---- 本机算出新口令的哈希（十六进制），密码明文不出本机 ----
  HASH_HEX=$( (python3 - "$ALGO" "$NEW_PASSWORD" "$SALT" "$ITER" 2>/dev/null || python - "$ALGO" "$NEW_PASSWORD" "$SALT" "$ITER") <<'PY'
import hashlib, sys
algo, pwd, salt, iters = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
print(hashlib.pbkdf2_hmac(algo, pwd.encode(), salt.encode(), iters).hex())
PY
  )
  echo "目标: $ENV_NAME / 库 $DB"
  echo "口令 '$NEW_PASSWORD' 的哈希（$ALGO, ${ITER} 次迭代, salt ${SALT:0:8}…）: ${HASH_HEX:0:24}…"
fi

# 标记表的 mode/note 按模式区分（注意：note 文本不能含 ASCII 单引号，会截断 SQL 字面量）
if [ "$PII_ONLY" = "1" ]; then
  MASK_MODE='prefix-suffix-pii-only'
  MASK_NOTE='email 加前缀1/phone 加后缀1；口令哈希未动（prod 口径 2026-08-07：保留 preprod 原口令与盐）'
else
  MASK_MODE='prefix-suffix'
  MASK_NOTE='email 加前缀1/phone 加后缀1/口令统一——注意该口径只断可达性不断身份，彻底去身份请跑 mask-residual-pii.sh --all'
fi
[ -n "$SKIP_EMAIL_PREFIX" ] && MASK_NOTE="$MASK_NOTE；排除 ${SKIP_EMAIL_PREFIX}* 开头邮箱未加前缀"

# email 的 UPDATE 生成语句按是否排除前缀分两个变体（排除版多一个 %I 参数与 NOT ILIKE 条件）
if [ -n "$SKIP_EMAIL_PREFIX" ]; then
  EMAIL_UPDATE_SELECT="SELECT format('UPDATE %I.%I SET %I = ''1'' || %I WHERE %I IS NOT NULL AND %I NOT LIKE ''1%%'' AND %I NOT ILIKE ''${SKIP_EMAIL_PREFIX}%%'';',
              table_schema, table_name, column_name, column_name, column_name, column_name, column_name)"
  EMAIL_RESIDUAL_EXTRA=" and email not ilike '${SKIP_EMAIL_PREFIX}%'"
else
  EMAIL_UPDATE_SELECT="SELECT format('UPDATE %I.%I SET %I = ''1'' || %I WHERE %I IS NOT NULL AND %I NOT LIKE ''1%%'';',
              table_schema, table_name, column_name, column_name, column_name, column_name)"
  EMAIL_RESIDUAL_EXTRA=""
fi

# ---- 远程脚本：动态遍历列 → 生成并执行 UPDATE ----
REMOTE=$(cat <<REOF
set -euo pipefail
EF=/opt/css-cicd/env/$ENV_NAME/backend.env
gv() { { grep -E "^\$1=" "\$EF" || true; } | tail -1 | cut -d= -f2- | tr -d '"\r'; }
export PGPASSWORD="\$(gv POSTGRES_PASSWORD)"
HOSTDB="\$(gv POSTGRES_HOST)"; USERDB="\$(gv POSTGRES_USER)"; DBNAME="\$(gv POSTGRES_DB)"
PSQL="docker run --rm -i -e PGPASSWORD=\$PGPASSWORD postgres:16 psql -h \$HOSTDB -U \$USERDB -d \$DBNAME -v ON_ERROR_STOP=1"

# 抽样表动态取（本库用户表叫 "user"，是 SQL 保留字，必须带引号；别的库可能叫别的名字）
SAMPLE_TBL=\$(\$PSQL -tAc "SELECT quote_ident(table_name) FROM information_schema.columns
  WHERE table_schema='public' AND column_name='email' AND data_type IN ('text','character varying')
  ORDER BY table_name='user' DESC LIMIT 1")
echo "--- 脱敏前抽样（表 \$SAMPLE_TBL）---"
[ -n "\$SAMPLE_TBL" ] && \$PSQL -tAc "select 'email: '||email from \$SAMPLE_TBL where email is not null limit 3" || true

# 生成 UPDATE 语句：email 前缀 1 / phone 后缀 1（只认文本列，排除枚举类 *type* 列）
\$PSQL -tAc "
$EMAIL_UPDATE_SELECT
FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%email%' AND column_name NOT ILIKE '%type%'
UNION ALL
-- phone 加后缀 1；与 email 同样做幂等保护（NOT LIKE '%1'），否则重跑一次多加一个 1。
-- 已知边界（2026-08-03 复检确认，本注释禁用 ASCII 双引号——它会截断外层 psql 的引号参数）：
--   值形态的幂等判断无法区分【已脱敏】和【原始值恰好以 1 结尾/开头】：首轮对全新导入的数据，
--   尾号为 1 的真实手机号（约 1/10）与 1 开头的真实邮箱（罕见）会被跳过而保留原值。
--   要 100% 覆盖需改用标记表/换脱敏形态（待拍板，见 05/README）。
SELECT format('UPDATE %I.%I SET %I = %I || ''1'' WHERE %I IS NOT NULL AND %I NOT LIKE ''%%1'';',
              table_schema, table_name, column_name, column_name, column_name, column_name)
FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%phone%' AND column_name NOT ILIKE '%type%'
" > /tmp/anon.sql
echo "--- 生成 \$(wc -l < /tmp/anon.sql) 条列级 UPDATE ---"

# 密码列：bytea 用 decode()，文本列直接写 hex（--emails-phones-only 模式跳过：不动口令）
if [ "$PII_ONLY" = "0" ]; then
\$PSQL -tAc "
SELECT format(CASE WHEN data_type='bytea'
                   THEN 'UPDATE %I.%I SET %I = decode(''$HASH_HEX'',''hex'');'
                   ELSE 'UPDATE %I.%I SET %I = ''$HASH_HEX'';' END,
              table_schema, table_name, column_name)
FROM information_schema.columns
WHERE table_schema='public' AND column_name ILIKE '%password%hash%'
" >> /tmp/anon.sql
fi

cat /tmp/anon.sql
echo "--- 执行（单事务）+ 写脱敏标记表 ---"
# 标记表：从此"这个库脱过敏没有"由标记决定，不再靠猜值形态（2026-08-03 加，与 mask-residual-pii.sh 共用同一张表）
{ echo 'BEGIN;'; cat /tmp/anon.sql
  echo "CREATE TABLE IF NOT EXISTS _css_pii_masked (id serial PRIMARY KEY, masked_at timestamptz NOT NULL DEFAULT now(), masked_by text NOT NULL, mode text NOT NULL, note text);"
  echo "INSERT INTO _css_pii_masked(masked_by, mode, note) VALUES ('anonymize-db.sh', '$MASK_MODE', '$MASK_NOTE');"
  echo 'COMMIT;'; } | \$PSQL
rm -f /tmp/anon.sql

echo "--- 脱敏后校验 ---"
[ -n "\$SAMPLE_TBL" ] && {
  \$PSQL -tAc "select 'email: '||email from \$SAMPLE_TBL where email is not null limit 3"
  \$PSQL -tAc "select '未加前缀的邮箱残留: '||count(*) from \$SAMPLE_TBL where email is not null and email not like '1%'$EMAIL_RESIDUAL_EXTRA"
}
# 真校验：为每个 password_hash 列生成"实际去重计数"查询再回喂执行（此前把常量 1 填进 format，
# 无论成败都打印 "1 种哈希 / 1 行"，等于没校验——2026-08-03 修）。
# ⚠️ PSQL 是 docker run（无卷挂载），容器看不见主机 /tmp——回喂必须走 stdin（同上方脱敏事务的管道模式），
#    不能用 psql -f 读文件（2026-08-03 二轮复检修正：-f 会报文件不存在，在 set -e 下把成功的脱敏误判成失败）。
# --emails-phones-only 模式跳过（口令未动，去重种数=1 的断言不成立也不该成立）。
if [ "$PII_ONLY" = "0" ]; then
\$PSQL -tAc "
SELECT format('SELECT ''%s.%s: ''||count(DISTINCT %I)||'' 种哈希 / ''||count(%I)||'' 行'' FROM %I.%I;',
              table_schema, table_name, column_name, column_name, table_schema, table_name)
FROM information_schema.columns
WHERE table_schema='public' AND column_name ILIKE '%password%hash%'" > /tmp/hashchk.sql
\$PSQL -tA < /tmp/hashchk.sql || true
# 断言：所有 password_hash 列的去重种数必须都是 1（脱敏后全库统一口令）
BAD=\$(\$PSQL -tA < /tmp/hashchk.sql | awk -F'[:/]' '{gsub(/[^0-9]/,"",\$2); if (\$2+0 > 1) c++} END{print c+0}')
[ "\${BAD:-0}" -eq 0 ] || { echo "[FATAL] 有 \$BAD 个 password_hash 列的哈希种数 >1，脱敏未彻底"; exit 1; }
rm -f /tmp/hashchk.sql
fi
REOF
)

PARAMS=$( (python3 - "$REMOTE" 2>/dev/null || python - "$REMOTE") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["1800"]}))
PY
)
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
# SSM 的 DescribeInstanceInformation 不允许标签过滤与其它过滤混用，先用 EC2 按标签取实例再核对在线
ID=$(awsq ec2 describe-instances --filters "Name=tag:Environment,Values=css-$ENV_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId')
if [ "$ID" != "None" ] && [ -n "$ID" ]; then
  ONLINE=$(awsq ssm describe-instance-information --filters "Key=InstanceIds,Values=$ID" --query 'InstanceInformationList[0].PingStatus')
  [ "$ONLINE" = "Online" ] || { echo "$ENV_NAME 应用机 $ID 未注册 SSM"; exit 1; }
fi
[ "$ID" != "None" ] && [ -n "$ID" ] || { echo "找不到在线的 $ENV_NAME 应用机"; exit 1; }
echo "在 $ID 上执行…"
CID=$(awsq ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
  --comment "anonymize css-$ENV_NAME" --parameters "$PARAMS" --query 'Command.CommandId')
while :; do
  ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query Status 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 10
done
echo "状态: $ST"
awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardOutputContent 2>/dev/null || true

# ⚠️ 失败必须非 0 退出：脱敏失败=库里仍有真实 PII，绝不能打印"完成"让人误以为安全（2026-08-03 修）
if [ "$ST" != "Success" ]; then
  awsq ssm get-command-invocation --command-id "$CID" --instance-id "$ID" --query StandardErrorContent 2>/dev/null | tail -20
  echo ""
  echo "[FATAL] 脱敏失败（状态 $ST）——库内可能仍有真实邮箱/手机号/口令哈希，排查后必须重跑"
  exit 1
fi

echo ""
if [ "$PII_ONLY" = "1" ]; then
  echo "===== 脱敏完成：email 前缀 1 / phone 后缀 1（口令哈希未动，原账号口令仍然有效）====="
else
  echo "===== 脱敏完成：所有账号口令现为 '$NEW_PASSWORD' ====="
  echo "提醒：口令哈希依赖 PASSWORD_SALT=${SALT:0:8}…；换环境/换盐后必须重跑本脚本，否则登录全失败"
fi
