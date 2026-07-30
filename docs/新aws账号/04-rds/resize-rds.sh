#!/usr/bin/env bash
# 调整 RDS 实例规格（升配/降配）。
# ⚠️ 改实例类型会【重启数据库】：单可用区约 2-5 分钟不可用，期间应用连库全部失败。
#    Multi-AZ 实例则是先改备库再切换，中断约 60 秒（生产上线后用这个）。
#
# 选型参考（2026-07-29 实测 css-non-prod 近 7 天负载）：
#   CPU 平均 3.6% / 峰值 29.7%      → CPU 不是瓶颈
#   可用内存 平均 146MB / 峰值 224MB → **内存才是瓶颈**（t4g.micro 只有 1GB）
#   连接数 平均 2.2 / 峰值 27
#   结论：升 db.t4g.small（2 vCPU / 2GB，内存翻倍）即可；t4g.medium(4GB) 属超配。
#
# ⚠️⚠️ FREE PLAN 拦截（2026-07-29 实测）：本账号是 Free plan，执行升配直接被拒——
#   `FreeTierRestrictionError: This instance size isn't available with free plan accounts.`
#   **Free plan 下 RDS 只能用 db.t4g.micro**；db.t4g.small 及以上、以及生产的 Multi-AZ／7 天备份
#   全部需要先把账号升级为 Paid plan。升级后本脚本一条命令即可完成升配，无需改动。
#
# 规格阶梯与价目（us-east-1 按需，不含存储）：
#   db.t4g.micro  2vCPU/1GB   ~$12/月
#   db.t4g.small  2vCPU/2GB   ~$24/月   ← 非生产当前目标
#   db.t4g.medium 2vCPU/4GB   ~$49/月
#   db.t4g.large  2vCPU/8GB   ~$98/月
#   db.m7g.large  2vCPU/8GB   ~$125/月（生产建议，非突发型，性能稳定）
#
# 用法: ./resize-rds.sh <实例标识> <新规格> [--now|--window]
#   --now    立即执行（马上重启，默认）
#   --window 排到下一个维护窗口执行（业务时段用这个）
#   例: ./resize-rds.sh css-non-prod db.t4g.small --now
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

DB_ID="${1:?用法: resize-rds.sh <实例标识> <新规格> [--now|--window]}"
NEW_CLASS="${2:?缺新规格，如 db.t4g.small}"
WHEN="${3:---now}"
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

CUR=$(awsq rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].[DBInstanceClass,MultiAZ,DBInstanceStatus]')
read -r CUR_CLASS MULTIAZ STATUS <<< "$CUR"
echo "实例 $DB_ID: 当前 $CUR_CLASS → 目标 $NEW_CLASS （Multi-AZ=$MULTIAZ, 状态=$STATUS）"
[ "$STATUS" = "available" ] || { echo "实例当前状态 $STATUS，非 available，拒绝操作"; exit 1; }
[ "$CUR_CLASS" != "$NEW_CLASS" ] || { echo "规格已经是 $NEW_CLASS，无需调整"; exit 0; }

if [ "$MULTIAZ" = "True" ]; then
  echo "Multi-AZ：先改备库再故障转移，中断约 60 秒"
else
  echo "[WARN] 单可用区：实例会【重启】，预计 2-5 分钟不可用——期间应用连库全部失败"
fi
case "$DB_ID" in
  *prod*) if [ "$DB_ID" = "css-prod" ]; then
            read -r -p "这是【生产】数据库，输入 prod 确认: " ok
            [ "$ok" = "prod" ] || { echo "已取消"; exit 1; }
          fi ;;
esac

case "$WHEN" in
  --now)    APPLY=(--apply-immediately);      echo "立即执行" ;;
  --window) APPLY=(--no-apply-immediately);   echo "排入下一个维护窗口" ;;
  *) echo "第三参数只能是 --now 或 --window"; exit 1 ;;
esac

aws --region "$REGION" rds modify-db-instance --db-instance-identifier "$DB_ID" \
  --db-instance-class "$NEW_CLASS" "${APPLY[@]}" >/dev/null
echo "已下发变更"

if [ "$WHEN" = "--now" ]; then
  echo -n "等待完成（modifying → available）"
  # 先等它进入 modifying，避免刚下发时还是 available 就误判成功
  for i in $(seq 1 30); do
    S=$(awsq rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0].DBInstanceStatus')
    [ "$S" != "available" ] && break
    echo -n "."; sleep 10
  done
  for i in $(seq 1 60); do
    S=$(awsq rds describe-db-instances --db-instance-identifier "$DB_ID" --query 'DBInstances[0].DBInstanceStatus')
    [ "$S" = "available" ] && break
    echo -n "."; sleep 20
  done
  echo ""
  NOW=$(awsq rds describe-db-instances --db-instance-identifier "$DB_ID" \
    --query 'DBInstances[0].[DBInstanceClass,DBInstanceStatus]')
  echo "===== 完成: $NOW ====="
  echo "别忘了验证应用能连上：bash ../01-vpc/rename-security-groups.sh verify （第 5 项就是连库检查）"
else
  echo "===== 已排期，将在维护窗口执行 ====="
  awsq rds describe-db-instances --db-instance-identifier "$DB_ID" \
    --query 'DBInstances[0].{窗口:PreferredMaintenanceWindow,待改:PendingModifiedValues.DBInstanceClass}'
fi
