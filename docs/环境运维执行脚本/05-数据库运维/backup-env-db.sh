#!/usr/bin/env bash
# 把 RDS（私有子网）某环境的业务库（css-<env>-main / css-<env>-ocr）经堡垒机 pg_dump 备份到本机文件。
#
# 链路：RDS ──VPC 内──> 堡垒机: pg_dump -Fc ──ssh stdout──> 本机落盘（堡垒机不留文件、无 S3 中转）。
# 本机不需要装 pg 客户端（pg_dump 用堡垒机上的 16.x，与 RDS PG16 匹配）。
#
# 用法:
#   SRC_PGPASSWORD='<账号密码>' ./backup-env-db.sh <test|uat|support-ref|support-demo|support-sync|prod> [输出目录]
# 例:
#   SRC_PGPASSWORD=... ./backup-env-db.sh test        # 落到 备份/数据库/test/test_{main,ocr}_<时间戳>.dump
#   SRC_PGPASSWORD=... ONLY=main ./backup-env-db.sh uat /d/dumps
#
# 可选环境变量:
#   SRC_DB_USER=css_ops    源库账号（默认 css_ops；密码见 deploy-env/密码.local.md，勿写进脚本/命令行历史外泄）
#   ONLY=main|ocr          只备份其中一个库（默认 main+ocr 都备）
#   DEV_KEY=<私钥路径>      用开发者自己的临时钥代替管理员钥
#
# 恢复对口脚本：restore-dump-via-gw.sh（本机 dump → S3 → 网关机 pg_restore 进 RDS）。
# 密码只经加密的 ssh 通道以 export 行送到远端 shell，不进远端命令行参数（ps 看不到）、不落盘。
set -uo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"  # git-bash: 防参数被误转成 Windows 路径

ENV_NAME="${1:?用法: SRC_PGPASSWORD=... backup-env-db.sh <test|uat|support-ref|support-demo|support-sync|prod> [输出目录]}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;; esac
: "${SRC_PGPASSWORD:?缺 SRC_PGPASSWORD（源 RDS 账号密码，见 deploy-env/密码.local.md）}"
SRC_DB_USER="${SRC_DB_USER:-css_ops}"
REGION=us-east-1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${2:-$SCRIPT_DIR/../../../备份/数据库/$ENV_NAME}"
TS="$(date +%Y%m%d_%H%M%S)"

# ---- 堡垒机 + RDS（按环境组；与 db-tunnel.sh 保持一致）----
SSH_DIR="$(cd "$SCRIPT_DIR/../../../deploy-env/ssh" && pwd)"
case "$ENV_NAME" in
  test|uat|support-ref|support-demo|support-sync) BASTION_IP=3.225.148.166; KEY="$SSH_DIR/css-non-prod-gw.pem"; RDS_ID=css-non-prod ;;
  prod)                                           BASTION_IP=34.225.237.45; KEY="$SSH_DIR/css-prod-bastion";    RDS_ID=css-prod ;;
esac
KEY="${DEV_KEY:-$KEY}"
[ -f "$KEY" ] || { echo "[FATAL] 找不到私钥 $KEY（管理员钥见 运维访问速查；开发者用 DEV_KEY=... 指定）"; exit 1; }

EP=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$RDS_ID" \
       --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null | tr -d '\r')
[ -n "$EP" ] && [ "$EP" != "None" ] || { echo "[FATAL] 查不到 RDS $RDS_ID 的地址"; exit 1; }

case "${ONLY:-both}" in
  main) DBS=("css-$ENV_NAME-main") ;;
  ocr)  DBS=("css-$ENV_NAME-ocr") ;;
  both) DBS=("css-$ENV_NAME-main" "css-$ENV_NAME-ocr") ;;
  *)    echo "[FATAL] ONLY 只能是 main|ocr"; exit 1 ;;
esac

echo "===== 备份计划 ====="
echo "  源: $RDS_ID ($EP) 账号 $SRC_DB_USER"
echo "  库: ${DBS[*]}"
echo "  落盘: $OUT_DIR/${ENV_NAME}_{main,ocr}_$TS.dump"

if [ "$ENV_NAME" = "prod" ]; then
  read -r -p "[WARN] 正在【把生产数据拷出 AWS 到本机】，输入 prod 确认: " ok < /dev/tty
  [ "$ok" = "prod" ] || { echo "已取消"; exit 1; }
fi

mkdir -p "$OUT_DIR"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20
          -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -i "$KEY")

FAIL=0
for DB in "${DBS[@]}"; do
  case "$DB" in *-main) TAG=main ;; *) TAG=ocr ;; esac
  OUT="$OUT_DIR/${ENV_NAME}_${TAG}_$TS.dump"
  [ -e "$OUT" ] && { echo "[FATAL] $OUT 已存在，不覆盖"; exit 1; }
  echo "--- pg_dump $DB → $OUT …"
  # 远端脚本经 stdin 送入：export 行传凭证，pg_dump 二进制流走 stdout 回本机；诊断走 stderr。
  {
    printf "export PGPASSWORD=%q EP=%q DB=%q USR=%q\n" "$SRC_PGPASSWORD" "$EP" "$DB" "$SRC_DB_USER"
    cat <<'REMOTE'
command -v pg_dump >/dev/null || { echo "[FATAL] 堡垒机缺 pg 客户端：sudo dnf install -y postgresql16" >&2; exit 1; }
exec pg_dump --format=custom --no-owner --no-privileges -h "$EP" -p 5432 -U "$USR" -d "$DB"
REMOTE
  } | ssh "${SSH_OPTS[@]}" ec2-user@"$BASTION_IP" bash -s > "$OUT"
  RC=$?
  # -Fc 文件头是 PGDMP；空文件/文本说明 dump 其实失败了
  if [ $RC -ne 0 ] || ! head -c 5 "$OUT" | grep -q PGDMP; then
    echo "[FATAL] $DB 备份失败（ssh 退出码 $RC；文件头: $(head -c 60 "$OUT" | tr -d '\0')）"
    rm -f "$OUT"; FAIL=1; continue
  fi
  echo "    ✅ $OUT （$(du -h "$OUT" | cut -f1)）"
done

[ "$FAIL" = 0 ] || { echo "===== 有库备份失败，见上方日志 ====="; exit 1; }
echo "===== 备份完成 ====="
echo "提醒: prod 数据未脱敏含真实 PII，备份文件勿外传；恢复用 restore-dump-via-gw.sh。"
