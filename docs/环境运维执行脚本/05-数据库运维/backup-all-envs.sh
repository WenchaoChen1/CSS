#!/usr/bin/env bash
# 一次备份多个环境的业务库（css-<env>-main / css-<env>-ocr），两种产物：
#   ① 本地文件：堡垒机上 pg_dump -Fc，经 ssh stdout 落到本机 备份/数据库/<env>/<env>_<main|ocr>_<时间戳>.dump
#   ② 库内副本：在【同一 RDS 实例内】复制成 backup_<日期>_<env>_<main|ocr>（test/uat 在 css-non-prod，prod 在 css-prod）
#
# 与 backup-env-db.sh（只落本地）/ backup-db-in-rds.sh（只做库内副本）相比：
#   - 本机不需要 aws CLI，也不需要任何数据库密码。本机只查 RDS 地址和 master secret 的 ARN
#     （先试 aws CLI，没有或失败就用 python boto3）；secret 的值在堡垒机上用实例角色现取，密码不出 AWS。
#     （堡垒机角色 css-gw-* 能读 rds! secret，但没有 rds:DescribeDBInstances，所以 ARN 必须本机查。）
#   - 一次跑多个环境，两种产物都防半成品：
#     本地文件先写 .part，pg_dump 成功且文件头是 PGDMP 才改成正式名；
#     库内副本先恢复到 <副本名>_inprogress，校验通过才改成正式名，失败就删掉这个临时库。
#   - 库内副本的校验：pg_dump / pg_restore 任一端非 0 即失败；源/副本的表数、alembic 版本不同即失败；
#     只有「表名=行数」清单不同时算「需人工确认」——多半是复制期间源库有写入，副本本身是 pg_dump 的一致快照。
#     （只比 public schema 的表数与行数，不校验数据内容。）
#
# 用法:
#   ./backup-all-envs.sh [--local|--rds] [test|uat|prod ...]
#     不给环境 = test uat prod 三个都做；不给 --local/--rds = 两种产物都做
# 例:
#   ./backup-all-envs.sh                      # 三个环境：本地文件 + 库内副本
#   ./backup-all-envs.sh --local test uat     # 只落本地文件
#   ONLY=main ./backup-all-envs.sh --rds prod # 只在 css-prod 内复制 main 库
#
# 可选环境变量:
#   ONLY=main|ocr        只处理其中一个库（默认 main+ocr）
#   DATE_TAG=<标签>       库内副本的日期标签，小写字母/数字/下划线，最长 30（默认今天 YYYYMMDD）
#   OUT_ROOT=<目录>       本地文件根目录（默认 工作区/备份/数据库，已 gitignore）
#   ASSUME_YES=1         跳过 prod 交互确认（无 tty 的自动化场景用）
#   AWS_PROFILE=<名>      本机查 RDS 用的 profile（默认 default = 新账号 582797602427）
#
# 退出码: 0=全部成功  1=有失败项  2=没有失败，但有副本行数与源库当前值不同，需人工确认
#
# 注意：
# - 副本已存在、或有上次中断留下的 <副本名>_inprogress 时跳过并记失败，绝不覆盖；副本 owner=postgres，自动给 css_dev 授只读。
# - 🚨 css-non-prod 是 test/uat 共用实例，副本用完要 DROP，别把共享磁盘堆满（见 README backup-db-in-rds.sh 段）。
# - prod 数据未脱敏（真实邮箱/手机号/口令哈希），本地文件勿外传。
# - pg_dump 带 --lock-wait-timeout=60s：遇到排队中的迁移锁会放弃而不是一直挂着；尽量避开 test/uat 推送部署的时段。
# - 前置：本机出口 IP 在堡垒机 22 端口白名单内，deploy-env/ssh/ 下有对应私钥（不支持 DEV_KEY：一次跑的环境可能跨两台堡垒机）。
set -uo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"  # git-bash: 防参数被误转成 Windows 路径

REGION=us-east-1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SSH_DIR="$ROOT_DIR/deploy-env/ssh"
OUT_ROOT="${OUT_ROOT:-$ROOT_DIR/备份/数据库}"
DATE_TAG="${DATE_TAG:-$(date +%Y%m%d)}"
TS="$(date +%Y%m%d_%H%M%S)"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20
          -o ServerAliveInterval=30 -o ServerAliveCountMax=3)

die() { echo "[FATAL] $*" >&2; exit 1; }

# 被 Ctrl-C / 关窗口打断时，删掉正在写的本地 .part 文件
CUR_PART=""
trap '[ -n "$CUR_PART" ] && rm -f "$CUR_PART"; echo "[中断] 已清理未写完的本地文件" >&2; exit 130' INT TERM HUP

# ---------- 参数 ----------
MODE=both
ENVS=()
for arg in "$@"; do
  case "$arg" in
    --local|--rds)
      want="${arg#--}"
      [ "$MODE" = both ] || [ "$MODE" = "$want" ] || die "--local 和 --rds 只能二选一（两种都要就都不写）"
      MODE="$want" ;;
    test|uat|prod) [[ " ${ENVS[*]-} " == *" $arg "* ]] || ENVS+=("$arg") ;;
    -h|--help) awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) die "未知参数: $arg（环境只能是 test|uat|prod）" ;;
  esac
done
[ ${#ENVS[@]} -gt 0 ] || ENVS=(test uat prod)

case "${ONLY:-both}" in
  main) TAGS=(main) ;;
  ocr)  TAGS=(ocr) ;;
  both) TAGS=(main ocr) ;;
  *)    die "ONLY 只能是 main|ocr" ;;
esac
# 长度上限 30：backup_<标签>_prod_main_inprogress 不能超过 PG 库名上限 63 字节（超了会被静默截断）
[[ "$DATE_TAG" =~ ^[a-z0-9_]{1,30}$ ]] || die "DATE_TAG 只能含小写字母/数字/下划线，最长 30：$DATE_TAG"

# ---------- 环境 → 堡垒机 / 私钥 / RDS 实例 ----------
env_conf() {  # 设置全局 BASTION_IP KEY RDS_ID
  case "$1" in
    test|uat) BASTION_IP=3.225.148.166; KEY="$SSH_DIR/css-non-prod-gw.pem"; RDS_ID=css-non-prod ;;
    prod)     BASTION_IP=34.225.237.45; KEY="$SSH_DIR/css-prod-bastion";    RDS_ID=css-prod ;;
  esac
}

find_py() {  # 找一个装了 boto3 的 python（Windows 上 python3 可能是商店占位程序，所以 python 优先）
  local p
  for p in python python3 py; do
    command -v "$p" >/dev/null 2>&1 && "$p" -c 'import boto3' >/dev/null 2>&1 && { echo "$p"; return 0; }
  done
  return 1
}

rds_info() {  # $1=RDS 实例 ID → 输出 "<endpoint> <master secret ARN>"；aws CLI 没有或失败时回退 boto3
  local out="" py
  if command -v aws >/dev/null 2>&1; then
    out=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$1" \
            --query 'DBInstances[0].[Endpoint.Address,MasterUserSecret.SecretArn]' --output text 2>/dev/null | tr -d '\r')
  fi
  if [ -z "$out" ]; then
    py=$(find_py) || { echo "[FATAL] 本机 aws CLI 不可用，也没有装了 boto3 的 python" >&2; return 1; }
    out=$("$py" - "$1" "$REGION" <<'PY' | tr -d '\r'
import sys, boto3
d = boto3.client("rds", sys.argv[2]).describe_db_instances(DBInstanceIdentifier=sys.argv[1])["DBInstances"][0]
print(d["Endpoint"]["Address"], d.get("MasterUserSecret", {}).get("SecretArn", "None"))
PY
)
  fi
  echo "$out"
}

# ---------- 远端脚本（经 stdin 送进堡垒机 bash -s） ----------
# 公共前导：在堡垒机上用实例角色取 master secret，导出 libpq 环境变量。诊断一律走 stderr（dump 模式的 stdout 是二进制流）。
remote_prelude() { cat <<'REMOTE'
set -uo pipefail
die() { echo "[FATAL] $*" >&2; exit 1; }
command -v pg_dump >/dev/null || die "堡垒机缺 pg 客户端：sudo dnf install -y postgresql16"
command -v python3 >/dev/null || die "堡垒机缺 python3"
command -v aws >/dev/null || die "堡垒机缺 aws CLI"
SECRET_JSON=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$ARN" \
                --query SecretString --output text) || die "取不到 master secret（堡垒机实例角色权限？）"
export SECRET_JSON
PGUSER=$(python3 -c 'import json,os;print(json.loads(os.environ["SECRET_JSON"])["username"])') || die "解析 secret 失败"
PGPASSWORD=$(python3 -c 'import json,os;print(json.loads(os.environ["SECRET_JSON"])["password"])') || die "解析 secret 失败"
unset SECRET_JSON
export PGUSER PGPASSWORD PGHOST="$EP" PGPORT=5432
REMOTE
}

remote_dump_body() { cat <<'REMOTE'
exec pg_dump --format=custom --no-owner --no-privileges --lock-wait-timeout=60s -d "$DB"
REMOTE
}

remote_copy_body() { cat <<'REMOTE'
P() { psql -d postgres -v ON_ERROR_STOP=1 -tA "$@"; }
P -c 'SELECT 1' >/dev/null || die "连不上 RDS $PGHOST（网络 / master 凭证）"
ROWCOUNT="(xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', tablename), false, true, '')))[1]::text"
FP_SQL="SELECT count(*)||' 表 / '||coalesce(sum(n),0)||' 行 / 行数清单md5 '||md5(coalesce(string_agg(t||'='||n, ',' ORDER BY t),''))
        FROM (SELECT tablename t, $ROWCOUNT::bigint n FROM pg_tables WHERE schemaname='public') x"
ROWS_SQL="SELECT tablename||'='||$ROWCOUNT FROM pg_tables WHERE schemaname='public' ORDER BY 1"
alembic_of() { psql -d "$1" -tA -c "SELECT string_agg(version_num, ',') FROM alembic_version" 2>/dev/null; }
db_exists() { [ "$(P -c "SELECT 1 FROM pg_database WHERE datname='$1'" | tr -d '[:space:]')" = 1 ]; }

grant_css_dev() {  # 副本用 TEMPLATE template0 建，不继承 template1 预置，css_dev 只读要在这里补
  [ "$(P -c "SELECT 1 FROM pg_roles WHERE rolname='css_dev'" | tr -d '[:space:]')" = 1 ] || return 0
  psql -d "$1" -v ON_ERROR_STOP=1 -q -c 'GRANT USAGE ON SCHEMA public TO css_dev;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO css_dev; GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO css_dev;' \
    && echo "    css_dev 只读已授" || echo "    ⚠️ css_dev 授权失败（副本本身可用）"
}

restore_into() {  # $1=源库 $2=已建好的空库；pg_dump / pg_restore 任一端非 0 即失败
  local st
  pg_dump --format=custom --no-owner --no-privileges --lock-wait-timeout=60s -d "$1" \
    | pg_restore --no-owner --no-privileges -d "$2"
  st=("${PIPESTATUS[@]}")   # 必须紧跟管道
  echo "    pg_dump 退出码 ${st[0]}，pg_restore 退出码 ${st[1]}"
  [ "${st[0]}" -eq 0 ] && [ "${st[1]}" -eq 0 ] || { echo "    ❌ 复制出错（见上方 pg_dump / pg_restore 报错）"; return 1; }
}

verify() {  # $1=源库 $2=副本 → 0=一致 1=失败 2=只有行数不同（需人工确认）
  local sfp dfp sal dal
  sfp=$(psql -d "$1" -tA -c "$FP_SQL"); dfp=$(psql -d "$2" -tA -c "$FP_SQL")
  sal=$(alembic_of "$1"); dal=$(alembic_of "$2")
  echo "    源:   ${sfp:-<查询失败>}  alembic=${sal:-无}"
  echo "    副本: ${dfp:-<查询失败>}  alembic=${dal:-无}"
  [ -n "$sfp" ] && [ -n "$dfp" ] || { echo "    ❌ 校验查询失败"; return 1; }
  [ "${sfp%% *}" = "${dfp%% *}" ] || { echo "    ❌ 表数不一致"; return 1; }
  [ "$sal" = "$dal" ] || { echo "    ❌ alembic 版本不一致"; return 1; }
  [ "$sfp" = "$dfp" ] && { echo "    表数、行数、alembic 全部一致"; return 0; }
  echo "    ⚠️ 表数、alembic 一致，但行数不同（多半是复制期间源库有写入），逐表差异："
  diff <(psql -d "$1" -tA -c "$ROWS_SQL") <(psql -d "$2" -tA -c "$ROWS_SQL") | head -20
  return 2
}

copy_one() {  # $1=源库 $2=副本库 → 0=成功 1=失败 2=成功但需人工确认
  local src=$1 dst=$2 tmp="$2_inprogress" v
  echo "--- $src → $dst"
  db_exists "$dst" && { echo "    ❌ $dst 已存在，绝不覆盖——换 DATE_TAG 或先 DROP"; return 1; }
  db_exists "$tmp" && { echo "    ❌ 有上次中断留下的半成品 $tmp，确认无用后先 DROP"; return 1; }
  P -c "CREATE DATABASE \"$tmp\" ENCODING 'UTF8' TEMPLATE template0" >/dev/null || { echo "    ❌ 建库 $tmp 失败"; return 1; }
  if restore_into "$src" "$tmp"; then verify "$src" "$tmp"; v=$?; else v=1; fi
  if [ "$v" = 1 ]; then
    P -c "DROP DATABASE \"$tmp\"" >/dev/null && echo "    已删除本次建的半成品 $tmp" \
      || echo "    ⚠️ 半成品 $tmp 删不掉，请手动 DROP"
    return 1
  fi
  grant_css_dev "$tmp"
  P -c "ALTER DATABASE \"$tmp\" RENAME TO \"$dst\"" >/dev/null \
    || { echo "    ❌ 改名 $tmp → $dst 失败，副本还在 $tmp"; return 1; }
  echo "    大小 $(P -c "SELECT pg_size_pretty(pg_database_size('$dst'))")"
  [ "$v" = 0 ] && echo "    ✅ $dst 完成" || echo "    ⚠️ $dst 已建好，但行数与源库当前值不同，请看上方差异确认"
  return "$v"
}

RC=0
for TAG in $TAGS; do
  copy_one "css-$ENVN-$TAG" "backup_${DATE_TAG}_${ENVN}_${TAG}"
  case $? in 0) ;; 2) [ "$RC" = 1 ] || RC=2 ;; *) RC=1 ;; esac
done
exit $RC
REMOTE
}

on_bastion() {  # stdin=远端脚本；用全局 BASTION_IP / KEY
  ssh "${SSH_OPTS[@]}" -i "$KEY" ec2-user@"$BASTION_IP" bash -s
}

# ---------- ① 本地文件 ----------
dump_env() {  # $1=env；用全局 EP ARN
  local env=$1 tag db out rc fail=0
  mkdir -p "$OUT_ROOT/$env" || return 1
  for tag in "${TAGS[@]}"; do
    db="css-$env-$tag"; out="$OUT_ROOT/$env/${env}_${tag}_$TS.dump"
    [ -e "$out" ] && { echo "    ❌ $out 已存在，不覆盖"; fail=1; continue; }
    CUR_PART="$out.part"
    { printf 'export REGION=%q ARN=%q EP=%q DB=%q\n' "$REGION" "$ARN" "$EP" "$db"
      remote_prelude; remote_dump_body; } | on_bastion > "$CUR_PART"
    rc=$?
    # ssh 退出码 = 远端 pg_dump 的退出码（断线是 255）；-Fc 文件头是 PGDMP，空文件/文本说明 dump 其实失败了
    if [ $rc -ne 0 ] || ! head -c 5 "$CUR_PART" | grep -q PGDMP; then
      echo "    ❌ $db 落本地失败（ssh 退出码 $rc）"; rm -f "$CUR_PART"; CUR_PART=""; fail=1; continue
    fi
    mv "$CUR_PART" "$out" || { echo "    ❌ 改名 $CUR_PART 失败"; rm -f "$CUR_PART"; CUR_PART=""; fail=1; continue; }
    CUR_PART=""
    echo "    ✅ $db → $out（$(du -h "$out" | cut -f1)）"
  done
  return $fail
}

# ---------- ② 库内副本 ----------
copy_env() {  # $1=env；用全局 EP ARN；返回远端退出码（0/1/2，ssh 自身出错是 255）
  { printf 'export REGION=%q ARN=%q EP=%q ENVN=%q DATE_TAG=%q TAGS=%q\n' \
      "$REGION" "$ARN" "$EP" "$1" "$DATE_TAG" "${TAGS[*]}"
    remote_prelude; remote_copy_body; } | on_bastion
}

# ---------- 主流程 ----------
echo "===== 备份计划 ====="
echo "  环境: ${ENVS[*]}   库: ${TAGS[*]}   产物: $MODE（local=本地文件 rds=库内副本 both=两种）"
[ "$MODE" != rds ]   && echo "  本地: $OUT_ROOT/<env>/<env>_<main|ocr>_$TS.dump"
[ "$MODE" != local ] && echo "  副本: backup_${DATE_TAG}_<env>_<main|ocr>（各自所在 RDS 实例内）"

if [[ " ${ENVS[*]} " == *" prod "* ]] && [ "${ASSUME_YES:-0}" != 1 ]; then
  read -r -p "[WARN] 包含 prod（未脱敏真实数据），输入 prod 确认: " ok < /dev/tty || ok=""
  [ "$ok" = prod ] || die "已取消"
fi

FAILED=()
WARNED=()
for env in "${ENVS[@]}"; do
  env_conf "$env"
  echo "===== $env（$RDS_ID，堡垒机 $BASTION_IP）====="
  [ -f "$KEY" ] || { echo "    ❌ 找不到私钥 $KEY"; FAILED+=("$env"); continue; }
  read -r EP ARN <<<"$(rds_info "$RDS_ID")"
  if [ -z "${EP:-}" ] || [ "$EP" = None ] || [ -z "${ARN:-}" ] || [ "$ARN" = None ]; then
    echo "    ❌ 查不到 $RDS_ID 的地址或托管 master secret（AWS 凭证/profile？）"; FAILED+=("$env"); continue
  fi
  if [ "$MODE" != rds ]; then
    echo "  [本地文件]"; dump_env "$env" || FAILED+=("$env:本地文件")
  fi
  if [ "$MODE" != local ]; then
    echo "  [库内副本]"; copy_env "$env"
    case $? in 0) ;; 2) WARNED+=("$env") ;; *) FAILED+=("$env:库内副本") ;; esac
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "===== 有失败项：${FAILED[*]}（见上方日志）====="
  exit 1
fi
if [ ${#WARNED[@]} -gt 0 ]; then
  echo "===== 完成，但这些环境的副本行数与源库当前值不同，需人工确认：${WARNED[*]} ====="
  exit 2
fi
echo "===== 全部完成 ====="
echo "提醒: 库内副本用完要 DROP（css-non-prod 是 test/uat 共用磁盘）；prod 本地文件含真实 PII，勿外传。"
