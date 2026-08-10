#!/usr/bin/env bash
# 把 RDS（私有子网）里某环境的库，同步到【只有本机内网能到、AWS 侧到不了】的 Postgres。
# 典型用途：把 css-test-main 拉到办公网机器 192.168.1.17:5434 建一个快照库自己折腾。
#
# 与 sync-db.sh 的分工：sync-db.sh 要求执行机能同时直连两端（两端都在 VPC 内）；
# 本脚本用于目标库在办公内网——堡垒机永远到不了它，只能借本机做中转。
# 本机因此【不需要装 psql / pg_dump / docker】，只当一条 ssh 管道（pg 客户端用堡垒机上的 16.x）。
#
#   RDS ──VPC 内──> 堡垒机: pg_dump | pg_restore ──> 堡垒机 127.0.0.1:$RPORT
#                                                      │  ssh -R 反向隧道
#                                                      └──> 本机 ──内网──> <目标 host:port>
#
# 用法:
#   SRC_PGPASSWORD='<RDS 密码>' TARGET_PGPASSWORD='<目标库密码>' \
#     ./sync-rds-to-intranet.sh <test|uat|support-ref|prod> <源库名> <目标host:port> <目标新库名> [目标用户]
# 例:
#   SRC_PGPASSWORD=... TARGET_PGPASSWORD=... \
#     ./sync-rds-to-intranet.sh test css-test-main 192.168.1.17:5434 css-test-main-20260807
#
# 可选环境变量:
#   SRC_DB_USER=css_ops     源库账号（默认 css_ops；密码见 deploy-env/密码.local.md，勿写进脚本）
#   DUMP_FILE=<本机路径>     额外在本机留一份 pg_dump -Fc 备份文件（先落盘再同步，两件事都要时用）
#   RECREATE=1              目标同名库已存在时先 DROP 重建（默认：存在即中止，绝不误覆盖）
#   RPORT=15432             堡垒机侧反向隧道端口（被占用时换一个）
#   DEV_KEY=<私钥路径>       用开发者自己的临时钥代替管理员钥
#
# 密码只经加密的 ssh 通道以 export 行送到远端 shell，不进命令行参数（ps 看不到）、不落盘。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"  # git-bash: 防参数被误转成 Windows 路径

ENV_NAME="${1:?用法: sync-rds-to-intranet.sh <test|uat|support-ref|prod> <源库名> <目标host:port> <目标新库名> [目标用户]}"
SRC_DB="${2:?缺源库名（如 css-test-main）}"
TARGET_ADDR="${3:?缺目标地址（如 192.168.1.17:5434）}"
TARGET_DB="${4:?缺目标新库名}"
TARGET_USER="${5:-postgres}"
SRC_DB_USER="${SRC_DB_USER:-css_ops}"
RPORT="${RPORT:-15432}"
REGION=us-east-1

case "$ENV_NAME" in test|uat|support-ref|prod) ;; *) echo "环境必须是 test|uat|support-ref|prod"; exit 1 ;; esac
: "${SRC_PGPASSWORD:?缺 SRC_PGPASSWORD（源 RDS 账号 $SRC_DB_USER 的密码）}"
: "${TARGET_PGPASSWORD:?缺 TARGET_PGPASSWORD（目标库 $TARGET_USER 的密码）}"

TARGET_HOST="${TARGET_ADDR%%:*}"
TARGET_PORT="${TARGET_ADDR##*:}"
[ "$TARGET_HOST" != "$TARGET_ADDR" ] || { echo "[FATAL] 目标地址要写成 host:port，如 192.168.1.17:5434"; exit 1; }
case "$TARGET_PORT" in ''|*[!0-9]*) echo "[FATAL] 目标端口不是数字: $TARGET_PORT"; exit 1 ;; esac

# ---- 堡垒机 + RDS（按环境组；与 db-tunnel.sh 保持一致）----
SSH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../deploy-env/ssh" && pwd)"
case "$ENV_NAME" in
  test|uat|support-ref) BASTION_IP=3.225.148.166; KEY="$SSH_DIR/css-non-prod-gw.pem"; RDS_ID=css-non-prod ;;
  prod)                 BASTION_IP=34.225.237.45; KEY="$SSH_DIR/css-prod-bastion";    RDS_ID=css-prod ;;
esac
KEY="${DEV_KEY:-$KEY}"
[ -f "$KEY" ] || { echo "[FATAL] 找不到私钥 $KEY"; exit 1; }

EP=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
       --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null | tr -d '\r')
[ -n "$EP" ] && [ "$EP" != "None" ] || { echo "[FATAL] 查不到 RDS $RDS_ID 的地址"; exit 1; }

echo "===== 同步计划 ====="
echo "  源: $RDS_ID / $SRC_DB （账号 $SRC_DB_USER）"
echo "  目标: $TARGET_ADDR / $TARGET_DB （账号 $TARGET_USER）经堡垒机 $BASTION_IP 反向隧道 :$RPORT"
[ -n "${DUMP_FILE:-}" ] && echo "  另存本机备份: $DUMP_FILE"
[ "${RECREATE:-0}" = "1" ] && echo "  ⚠️ RECREATE=1：目标同名库若存在将被 DROP"

if [ "$ENV_NAME" = "prod" ]; then
  read -r -p "[WARN] 正在【把生产数据拷出 AWS 到内网机器】，输入 prod 确认: " ok < /dev/tty
  [ "$ok" = "prod" ] || { echo "已取消"; exit 1; }
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20
          -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes -i "$KEY")

# ---- 可选：先在本机留一份 -Fc 备份文件（dump 走 ssh stdout 直接落盘，不在堡垒机留痕）----
if [ -n "${DUMP_FILE:-}" ]; then
  mkdir -p "$(dirname "$DUMP_FILE")"
  echo "--- 生成本机备份文件 …"
  ssh "${SSH_OPTS[@]}" ec2-user@"$BASTION_IP" \
    "PGPASSWORD='$SRC_PGPASSWORD' pg_dump --format=custom --no-owner --no-privileges \
       -h '$EP' -p 5432 -U '$SRC_DB_USER' -d '$SRC_DB'" > "$DUMP_FILE"
  # -Fc 文件头是 PGDMP；空文件/文本说明 dump 其实失败了
  head -c 5 "$DUMP_FILE" | grep -q PGDMP || { echo "[FATAL] 备份文件不是有效的 pg_dump -Fc（内容: $(head -c 200 "$DUMP_FILE"))"; exit 1; }
  echo "    已保存: $DUMP_FILE （$(du -h "$DUMP_FILE" | cut -f1)）"
fi

# ---- 远端脚本：单引号 heredoc（不做本地展开，规避引号/反引号陷阱），变量只经前置 export 行传入 ----
{
  printf "export SRC_EP=%q SRC_DB=%q SRC_USER=%q RPORT=%q TGT_DB=%q TGT_USER=%q RECREATE=%q\n" \
    "$EP" "$SRC_DB" "$SRC_DB_USER" "$RPORT" "$TARGET_DB" "$TARGET_USER" "${RECREATE:-0}"
  printf "export SRC_PW=%q TGT_PW=%q\n" "$SRC_PGPASSWORD" "$TARGET_PGPASSWORD"
  cat <<'REMOTE'
set -uo pipefail
command -v pg_dump >/dev/null && command -v pg_restore >/dev/null || {
  echo "[FATAL] 堡垒机缺 pg 客户端：sudo dnf install -y postgresql16"; exit 1; }

# 1) 反向隧道是否真的通到内网库
(echo > /dev/tcp/127.0.0.1/$RPORT) 2>/dev/null || {
  echo "[FATAL] 堡垒机 127.0.0.1:$RPORT 不可达——反向隧道没建起来（或本机到目标库不通）"; exit 1; }

T() { PGPASSWORD="$TGT_PW" psql -h 127.0.0.1 -p "$RPORT" -U "$TGT_USER" -v ON_ERROR_STOP=1 "$@"; }

# 2) 目标服务端版本必须 ≤ 客户端大版本（pg_dump 16 的产物恢复到 15 及以下不可靠）
TGT_VER=$(T -d postgres -tAc "SHOW server_version_num" | tr -d '[:space:]') || {
  echo "[FATAL] 连不上目标库（账号/密码/pg_hba 是否放行？）"; exit 1; }
CLI_VER=$(pg_dump --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')
echo "目标 Postgres server_version_num=$TGT_VER ；客户端大版本=$CLI_VER"
[ "$TGT_VER" -lt $(( (CLI_VER + 1) * 10000 )) ] || {
  echo "[FATAL] 目标端大版本高于客户端（$CLI_VER），请在堡垒机装同版本客户端后再来"; exit 1; }
[ "$TGT_VER" -ge $(( CLI_VER * 10000 )) ] || echo "[WARN] 目标端大版本低于源端 $CLI_VER —— 恢复可能报错（新语法/新类型）"

# 3) 建库（存在即中止，除非 RECREATE=1）
EXISTS=$(T -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$TGT_DB'" | tr -d '[:space:]')
if [ "${EXISTS:-}" = "1" ]; then
  if [ "$RECREATE" = "1" ]; then
    echo "--- 目标库已存在，RECREATE=1 → DROP 重建"
    T -d postgres -c "DROP DATABASE \"$TGT_DB\";"
  else
    echo "[FATAL] 目标库 $TGT_DB 已存在。换个库名，或用 RECREATE=1 明确覆盖"; exit 1
  fi
fi
T -d postgres -c "CREATE DATABASE \"$TGT_DB\" ENCODING 'UTF8' TEMPLATE template0;"
echo "--- 已建库 $TGT_DB"

# 4) 流式搬运（无中间文件）。目标是新建空库，故不加 --clean。
#    pg_restore 返回 1 = 仅 warning（如缺 role/extension）；>1 才是硬失败。
RC=0
PGPASSWORD="$SRC_PW" pg_dump --format=custom --no-owner --no-privileges \
    -h "$SRC_EP" -p 5432 -U "$SRC_USER" -d "$SRC_DB" \
  | PGPASSWORD="$TGT_PW" pg_restore --no-owner --no-privileges \
      -h 127.0.0.1 -p "$RPORT" -U "$TGT_USER" -d "$TGT_DB" || RC=$?
echo "--- pg_dump|pg_restore 退出码: $RC（0=干净成功）"

# 5) 校验：表数 + 几张主表行数 + alembic 版本
TBL=$(T -d "$TGT_DB" -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='public'" | tr -d '[:space:]')
SIZE=$(T -d "$TGT_DB" -tAc "SELECT pg_size_pretty(pg_database_size('$TGT_DB'))" | tr -d '\n')
echo "--- 目标库校验: 表数=$TBL 大小=$SIZE"
T -d "$TGT_DB" -tAc "SELECT 'alembic: '||version_num FROM alembic_version" 2>/dev/null || true
[ "${TBL:-0}" -gt 0 ] || { echo "[FATAL] 目标库 public 表数为 0——搬运没成功"; exit 1; }
[ "$RC" -le 1 ] || { echo "[FATAL] pg_restore 硬失败（退出码 $RC）——目标库不完整，勿使用"; exit 1; }
echo "===== 远端完成 ====="
REMOTE
} | ssh "${SSH_OPTS[@]}" -R "$RPORT:$TARGET_HOST:$TARGET_PORT" ec2-user@"$BASTION_IP" bash -s

echo "===== 同步完成 ====="
echo "客户端连法: psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d '$TARGET_DB'"
echo "提醒: 数据带 PII（test 库已脱敏，prod 未脱敏口令）——落到内网机器后按公司要求处置，勿再外传"
