#!/usr/bin/env bash
# 单独修改某一个数据库账号的密码（不动其他账号、不动授权）。
# 适用账号: css_app_test / css_app_uat / css_app_prod / css_dev / css_ops（master postgres 的密码
#           由 Secrets Manager 托管，改它用: aws secretsmanager rotate-secret，不用本脚本）。
#
# 用法:
#   ./change-db-password.sh <rds主机> <master密码> <账号名>              # 随机生成 20 位字母数字并打印
#   ./change-db-password.sh <rds主机> <master密码> <账号名> '<新密码>'    # 用指定密码（建议纯字母数字，免 URL 转义）
#
# ⚠️ 在 VPC 内机器执行（应用机/网关机；psql 走 docker postgres:16）。
# 改完记得: ① 抄进 运维访问速查.local.md；② 若该账号被应用使用 → 改 deploy-env/<env>/backend.env
#           相应 3 处 → put-params.sh <env> → deploy-env.sh <env> core 重启生效。
set -euo pipefail

HOST="${1:?用法: change-db-password.sh <rds主机> <master密码> <账号名> [新密码]}"
PASS="${2:?缺 master 密码}"
ROLE="${3:?缺账号名，如 css_dev}"
NEWPW="${4:-}"

case "$ROLE" in
  postgres) echo "master 密码由 Secrets Manager 托管，请用: aws secretsmanager rotate-secret --secret-id <rds!secretARN>"; exit 1 ;;
  css_app_test|css_app_uat|css_app_prod|css_dev|css_ops) ;;
  *) echo "⚠️ 非常规账号 [$ROLE]，确认无误则继续"; ;;
esac

# 输入校验（2026-08-03 加）：角色名与密码都会拼进 SQL，不校验则含单引号即语句破裂、可注入任意 SQL（以 master 身份）
[[ "$ROLE" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || { echo "[FATAL] 角色名只允许小写字母/数字/下划线（首字符非数字）: $ROLE"; exit 1; }

[ -n "$NEWPW" ] || NEWPW=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
[[ "$NEWPW" =~ ^[A-Za-z0-9]{12,}$ ]] || { echo "[FATAL] 密码只允许纯字母数字且 ≥12 位（避免 SQL/URL 转义问题）"; exit 1; }

docker run --rm -e PGPASSWORD="$PASS" postgres:16 psql -h "$HOST" -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -c "ALTER ROLE \"${ROLE}\" LOGIN PASSWORD '${NEWPW}';"

echo "===== 密码已修改 ====="
printf '%-14s %s\n' "$ROLE" "$NEWPW"
echo "（请立刻抄进 运维访问速查.local.md；本输出不留存）"
