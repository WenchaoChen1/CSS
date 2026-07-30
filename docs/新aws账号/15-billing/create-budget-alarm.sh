#!/usr/bin/env bash
# 账单告警：**每日**实际消费超过阈值就发邮件。
#
# 为什么用 AWS Budgets 而不是 CloudWatch 账单告警：
#   CloudWatch 的 AWS/Billing→EstimatedCharges 指标是【当月累计】估算值，只能做"这个月花超了"，
#   做不到"今天花超了"——月初怎么烧都不会触发，等触发时钱已经花完了。
#   AWS Budgets 支持 DAILY 周期 + ACTUAL 实际花费，才是"每天超 $X 就叫我"的正确工具。
#
# 成本：每个账号**前 2 个预算免费**，之后 $0.02/预算/天。本脚本只建 1 个预算（两个阈值放在
#   同一个预算里做两条通知），所以是免费的。
#
# 通知延迟：AWS 的账单数据本身有 8-12 小时延迟，所以"今天超了"的邮件通常次日早上到——
#   这是 AWS 账单系统的固有延迟，不是配置问题。要实时感知成本只能靠资源侧告警（CloudWatch）。
#
# 用法: ./create-budget-alarm.sh [日预算上限] [邮箱1] [邮箱2] ...
#   例: ./create-budget-alarm.sh 40 charles@shinypathway.com 2219002126@qq.com
#   默认在 $上限的 50% 与 100% 两档告警（40 → $20 和 $40）
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

LIMIT="${1:-40}"
shift || true
EMAILS=("$@")
[ ${#EMAILS[@]} -gt 0 ] || { echo "至少给一个邮箱: ./create-budget-alarm.sh 40 a@b.com [c@d.com]"; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
BUDGET_NAME="css-daily-cost"
HALF=$(awk "BEGIN{printf \"%.0f\", $LIMIT/2}")

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMPF=$(cygpath -m "$TMP"); else TMPF="$TMP"; fi

cat > "$TMP/budget.json" <<EOF
{
  "BudgetName": "$BUDGET_NAME",
  "BudgetLimit": { "Amount": "$LIMIT", "Unit": "USD" },
  "TimeUnit": "DAILY",
  "BudgetType": "COST",
  "CostTypes": {
    "IncludeTax": true, "IncludeSubscription": true, "UseBlended": false,
    "IncludeRefund": false, "IncludeCredit": false, "IncludeUpfront": true,
    "IncludeRecurring": true, "IncludeOtherSubscription": true, "IncludeSupport": true,
    "IncludeDiscount": true, "UseAmortized": false
  }
}
EOF

# 两档通知：超过一半提前预警、超过上限紧急。
# 注意 DAILY 预算【只支持 ACTUAL 通知】，不支持 FORECASTED（AWS 限制：
#   "DAILY budget only supports notification type as ACTUAL"）；要预测告警得另建 MONTHLY 预算。
# IncludeCredit=false 很关键——
# 否则 credits 抵扣后账面永远是 0，等 credits 用完才突然爆炸。
SUBS=$(printf '{"SubscriptionType":"EMAIL","Address":"%s"},' "${EMAILS[@]}"); SUBS="[${SUBS%,}]"
cat > "$TMP/notify.json" <<EOF
[
  { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN",
      "Threshold": $HALF, "ThresholdType": "ABSOLUTE_VALUE" },
    "Subscribers": $SUBS },
  { "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN",
      "Threshold": $LIMIT, "ThresholdType": "ABSOLUTE_VALUE" },
    "Subscribers": $SUBS }
]
EOF

if aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" >/dev/null 2>&1; then
  echo "预算已存在，更新阈值与订阅者: $BUDGET_NAME"
  aws budgets update-budget --account-id "$ACCOUNT_ID" --new-budget "file://$TMPF/budget.json"
  # 通知得逐条重建（API 不支持整体替换）
  for t in $(aws budgets describe-notifications-for-budget --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" \
              --query 'Notifications[].Threshold' --output text | tr -d '\r'); do
    aws budgets delete-notification --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" \
      --notification "{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":$t,\"ThresholdType\":\"ABSOLUTE_VALUE\"}" 2>/dev/null || true
    aws budgets delete-notification --account-id "$ACCOUNT_ID" --budget-name "$BUDGET_NAME" \
      --notification "{\"NotificationType\":\"FORECASTED\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":$t,\"ThresholdType\":\"ABSOLUTE_VALUE\"}" 2>/dev/null || true
  done
  ( python3 - "$TMPF/notify.json" "$ACCOUNT_ID" "$BUDGET_NAME" 2>/dev/null || python - "$TMPF/notify.json" "$ACCOUNT_ID" "$BUDGET_NAME" ) <<'PY'
import json, subprocess, sys
path, acct, name = sys.argv[1], sys.argv[2], sys.argv[3]
for item in json.load(open(path, encoding='utf-8')):
    subprocess.run(['aws','budgets','create-notification','--account-id',acct,'--budget-name',name,
                    '--notification', json.dumps(item['Notification']),
                    '--subscribers', json.dumps(item['Subscribers'])], check=False)
PY
else
  aws budgets create-budget --account-id "$ACCOUNT_ID" \
    --budget "file://$TMPF/budget.json" \
    --notifications-with-subscribers "file://$TMPF/notify.json"
  echo "预算创建: $BUDGET_NAME"
fi

echo ""
echo "===== 账单告警就绪 ====="
echo "预算: $BUDGET_NAME（周期 每日，上限 \$$LIMIT）"
echo "触发条件（三条）："
echo "  1) 当日实际消费 > \$$HALF   → 提前预警"
echo "  2) 当日实际消费 > \$$LIMIT  → 超限"
echo "  （DAILY 预算不支持预测告警，AWS 限制；需要预测就另建月度预算）"
echo "收件人: ${EMAILS[*]}"
echo ""
echo "注意："
echo "  · AWS 账单数据有 8-12 小时延迟，超限邮件一般次日早上到（这是账单系统固有延迟）"
echo "  · CostTypes 里 IncludeCredit=false：credits 抵扣的部分【也算消费】，"
echo "    否则有 credits 时账面永远 0，等 credits 耗尽才突然爆表"
echo "  · Budgets 邮件来自 no-reply@budgets.alerts.amazonaws.com，**先去垃圾箱把它加白名单**"
echo "查看: https://us-east-1.console.aws.amazon.com/billing/home#/budgets"
