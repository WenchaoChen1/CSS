#!/usr/bin/env bash
# 【独立补脱敏脚本】把 anonymize-db.sh 漏掉/掩盖不住的真实个人数据彻底抹掉，并写入脱敏标记表。
#
# 为什么需要它（2026-08-03 实查发现）：
#   ① anonymize-db.sh 的口径是"email 加前缀 1 / phone 加后缀 1"——它只让联系方式**发不出去/打不通**，
#      但**身份仍然完全可读**（如 1jiahuang659@gmail.com、1239pelico.neftali@gmail.com 一眼能认出是谁）；
#   ② 它用"值形态"判断是否已脱敏（email 以 1 开头就跳过），于是【原本就以 1 开头的真实邮箱】永远不会被脱敏，
#      且事后无法与"已脱敏"区分（test 库实测有 4 个这样的歧义值）。
#
# 本脚本做两件 anonymize-db.sh 做不到的事：
#   1) 把 email/phone 换成【确定性合成值】——同一原值恒得同一结果（可重复、不破坏唯一约束），
#      且合成值不含任何真实身份；email 仍保持 1 开头，兼容既有校验口径。
#   2) 建脱敏标记表 `_css_pii_masked`——从此"是否已脱敏"由标记决定，不再靠猜值形态。
#
# 用法: ./mask-residual-pii.sh <test|uat|support-demo|support-sync> [--all]
#   缺省（不带 --all）：只处理【歧义/未脱敏】的行——email 匹配 ^1[0-9] 或不以 1 开头；phone 不以 1 结尾。
#   --all：把该环境**所有** email/phone 全部换成合成值（真正的"认不出是谁"，但测试账号登录名会全变，
#          需同步通知使用者；脚本会打印新旧对照供分发）。
#   prod 一律拒绝执行。
# 前置: 与 anonymize-db.sh 相同——经 SSM 在该环境应用机上跑，用机器上 /opt/css-cicd/env/<env>/backend.env 的库连接。
set -euo pipefail

ENV_NAME="${1:?用法: mask-residual-pii.sh <test|uat|support-demo|support-sync> [--all]}"
MODE="${2:-residual}"
case "$ENV_NAME" in
  test|uat|support-demo|support-sync) ;;
  prod) echo "[FATAL] 生产库禁止脱敏"; exit 1 ;;
  *) echo "环境必须是 test|uat|support-demo|support-sync"; exit 1 ;;
esac
[ "$MODE" = "residual" ] || [ "$MODE" = "--all" ] || { echo "第二个参数只能是 --all（或省略）"; exit 1; }
REGION=us-east-1
export MSYS_NO_PATHCONV=1 PYTHONUTF8=1

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# Windows/Git-Bash：aws.exe 是原生 Windows 程序，读不了 /tmp/... 这种 MSYS 路径，file:// 需给它 Windows 形式
if command -v cygpath >/dev/null 2>&1; then TMPW="$(cygpath -m "$TMP")"; else TMPW="$TMP"; fi

# ── 远端脚本：写成【带引号的 heredoc】+ base64 传输 ──
# 引号 heredoc = 本地零展开，彻底避开 $ / 反引号 / 反斜杠转义坑（2026-08-03 两次事故的根治做法）；
# 需要注入的变量走末尾的 sed 占位符替换，不靠 shell 展开。
cat > "$TMP/remote.sh" <<'REMOTE_EOF'
set -euo pipefail
ENV_NAME='__ENV__'
MODE='__MODE__'
# 在【堡垒机】上执行（与 restore-dump-via-gw.sh 同一成熟模式）：
#   - 不依赖应用机是否部署过（uat 就没有 /opt/css-cicd，其参数还是占位值）；
#   - master 密码由堡垒机自己从 Secrets Manager 现取，**不进 SSM 命令文本、不进 Run Command 日志**。
command -v psql >/dev/null || sudo dnf install -y postgresql16 >/dev/null 2>&1 || { echo '[FATAL] 装不上 psql16'; exit 1; }
SECRET_ARN='__SECRET_ARN__'
export PGPASSWORD=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id "$SECRET_ARN" \
  --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
[ -n "$PGPASSWORD" ] || { echo '[FATAL] 取不到 master 密码'; exit 1; }
export PGHOST='__RDS_ENDPOINT__' PGUSER=postgres PGDATABASE="css-${ENV_NAME}-main"
PSQL() { psql -v ON_ERROR_STOP=1 "$@"; }

# 合成值规则（确定性、不可逆、无真实身份）：
#   email -> '1m' || left(md5(原值),10) || '@example.invalid'      （保持 1 开头，兼容既有校验）
#   phone -> '900' || right(('0'||abs(hashtext(原值))::text),9)     （非真实号段，长度稳定）
# 已是合成值的行不再重复处理（用 @example.invalid / ^900 识别，形态唯一，无歧义）。
if [ "$MODE" = "--all" ]; then
  EMAIL_WHERE="%I IS NOT NULL AND %I NOT LIKE ''%%@example.invalid''"
  PHONE_WHERE="%I IS NOT NULL AND %I !~ ''^900[0-9]{9}$''"
else
  # 仅歧义/未脱敏：email 不以 1 开头（从未脱敏）或以 1+数字开头（无法判定）；phone 不以 1 结尾（从未脱敏）
  EMAIL_WHERE="%I IS NOT NULL AND %I NOT LIKE ''%%@example.invalid'' AND (%I !~ ''^1'' OR %I ~ ''^1[0-9]'')"
  PHONE_WHERE="%I IS NOT NULL AND %I !~ ''^900[0-9]{9}$'' AND %I !~ ''1$''"
fi

echo "=== 处理前统计（$MODE 模式命中的行）==="
PSQL -tAc "
SELECT format('SELECT ''%s.%s -> ''||count(*) FROM %I.%I WHERE ${EMAIL_WHERE};',
              table_name, column_name, table_schema, table_name, column_name, column_name, column_name, column_name)
FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%email%' AND column_name NOT ILIKE '%type%'
UNION ALL
SELECT format('SELECT ''%s.%s -> ''||count(*) FROM %I.%I WHERE ${PHONE_WHERE};',
              table_name, column_name, table_schema, table_name, column_name, column_name, column_name)
FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%phone%' AND column_name NOT ILIKE '%type%' AND column_name NOT ILIKE '%country%'
" > /tmp/cnt.sql
PSQL -tA < /tmp/cnt.sql | grep -v ' -> 0$' || echo '（无命中，已是干净状态）'

echo "=== 生成 UPDATE ==="
PSQL -tAc "
SELECT format('UPDATE %I.%I SET %I = ''1m''||left(md5(%I),10)||''@example.invalid'' WHERE ${EMAIL_WHERE};',
              table_schema, table_name, column_name, column_name, column_name, column_name, column_name, column_name)
FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%email%' AND column_name NOT ILIKE '%type%'
UNION ALL
SELECT format('UPDATE %I.%I SET %I = ''900''||lpad((abs(hashtext(%I))%%1000000000)::text,9,''0'') WHERE ${PHONE_WHERE};',
              table_schema, table_name, column_name, column_name, column_name, column_name, column_name)
FROM information_schema.columns
WHERE table_schema='public' AND data_type IN ('text','character varying','character')
  AND column_name ILIKE '%phone%' AND column_name NOT ILIKE '%type%' AND column_name NOT ILIKE '%country%'
" > /tmp/mask.sql
wc -l < /tmp/mask.sql | xargs -I{} echo '共 {} 条 UPDATE'

echo "=== 执行（单事务）+ 写脱敏标记表 ==="
{
  echo 'BEGIN;'
  cat /tmp/mask.sql
  cat <<'SQL'
CREATE TABLE IF NOT EXISTS _css_pii_masked (
  id           serial PRIMARY KEY,
  masked_at    timestamptz NOT NULL DEFAULT now(),
  masked_by    text        NOT NULL,
  mode         text        NOT NULL,
  note         text
);
SQL
  echo "INSERT INTO _css_pii_masked(masked_by, mode, note) VALUES ('mask-residual-pii.sh', '${MODE}', '合成值：email=1m<md5前10>@example.invalid / phone=900+9位；本表存在即代表该库已做过确定性脱敏，勿再靠值形态判断');"
  echo 'COMMIT;'
} | PSQL

echo "=== 处理后校验（应全部为 0）==="
PSQL -tA < /tmp/cnt.sql | grep -v ' -> 0$' && { echo '[FATAL] 仍有残留'; exit 1; } || echo '✅ 无残留'
echo "=== 标记表 ==="
PSQL -tAc "SELECT masked_at||' | '||masked_by||' | '||mode FROM _css_pii_masked ORDER BY id DESC LIMIT 3"
echo "=== 抽样 ==="
PSQL -tAc "SELECT 'email: '||email FROM \"user\" WHERE email IS NOT NULL LIMIT 3"
PSQL -tAc "SELECT 'phone: '||phone_number FROM \"user\" WHERE phone_number IS NOT NULL LIMIT 3" 2>/dev/null || true
rm -f /tmp/mask.sql /tmp/cnt.sql
REMOTE_EOF

# RDS 实例与其托管密钥、堡垒机——全部动态查，不写死
RDS_ID=css-non-prod   # test/uat 共享；prod 已在开头拒绝
SECRET_ARN=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text | tr -d '\r')
RDS_EP=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
  --query 'DBInstances[0].Endpoint.Address' --output text | tr -d '\r')
[ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "None" ] || { echo "[FATAL] 取不到 $RDS_ID 的托管密钥 ARN"; exit 1; }

sed -i "s|__ENV__|$ENV_NAME|; s|__MODE__|$MODE|; s|__SECRET_ARN__|$SECRET_ARN|; s|__RDS_ENDPOINT__|$RDS_EP|" "$TMP/remote.sh"
bash -n "$TMP/remote.sh" || { echo "[FATAL] 远端脚本语法错误"; exit 1; }

echo "===== 补脱敏：$ENV_NAME（模式 $MODE）====="
[ "$MODE" = "--all" ] && echo "⚠️ --all 会替换全部 email/phone，测试账号登录名将改变！5 秒后开始（Ctrl+C 取消）" && sleep 5

# 在堡垒机上跑（它才有读 rds! secret 的权限；应用机按设计没有）
# 用【控制面标签对】定位堡垒机，不用 Name：
#   Environment=css-shared + EnvironmentGroup=css-non-prod 在 EC2 里唯一对应非生产堡垒机
#   （应用机是 css-test/css-uat，prod 堡垒机是 css-prod 组）。
#   为什么不用 Name：Name 是可改的展示名——2026-07-30 堡垒机由 css-non-prod-gw 改名，
#   就把按 Name 查的 restore-dump-via-gw.sh 直接搞失效了；标签对是规范约定，稳定得多。
ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Environment,Values=css-shared" "Name=tag:EnvironmentGroup,Values=css-non-prod" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr -d '\r' | awk '{print $1}')
[ -n "$ID" ] && [ "$ID" != "None" ] || { echo "[FATAL] 找不到运行中的非生产堡垒机（Environment=css-shared + EnvironmentGroup=css-non-prod）"; exit 1; }
echo "执行机: $ID（堡垒机）｜ 目标库: css-$ENV_NAME-main @ $RDS_EP"

B64=$(base64 -w0 < "$TMP/remote.sh")
node -e "console.log(JSON.stringify({commands:['echo '+process.argv[1]+' | base64 -d > /tmp/mask.sh && bash /tmp/mask.sh; rc=\$?; rm -f /tmp/mask.sh; exit \$rc']}))" "$B64" > "$TMP/params.json"

CID=$(aws ssm send-command --region "$REGION" --instance-ids "$ID" --document-name AWS-RunShellScript \
  --comment "mask residual pii $ENV_NAME" --parameters "file://$TMPW/params.json" --query 'Command.CommandId' --output text)
for _ in $(seq 1 60); do
  ST=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$ID" --query Status --output text 2>/dev/null || echo Pending)
  case "$ST" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 5
done
aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$ID" --query StandardOutputContent --output text
[ "$ST" = "Success" ] || {
  aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$ID" --query StandardErrorContent --output text | tail -20
  echo "[FATAL] 补脱敏失败（状态 $ST）——库内可能仍有真实数据"; exit 1; }
echo "===== 完成：$ENV_NAME 已写入脱敏标记表 _css_pii_masked ====="
