#!/usr/bin/env bash
# 停机 / 启动 / 查看某环境的应用 EC2（css-<env>-app），用于暂停不常用环境省钱（stopped 实例只计 EBS 费）。
# 用法: ./ec2-power.sh <stop|start|status> <env> [env ...]     env ∈ test|uat|support-ref|support-demo|support-sync|prod
#   ./ec2-power.sh stop support-ref support-demo support-sync   # 2026-09-04 首用：暂停三台 support 机
#   ./ec2-power.sh start support-demo                            # 恢复（容器 restart=always/unless-stopped 随机自起，三栈约 2 分钟内可用）
#   ./ec2-power.sh status support-ref support-demo support-sync  # 只读查看
# 行为：
#   stop  = 先 disable-alarm-actions 该环境全部 css-<env>-* 告警（否则 alb-no-healthy-target / ec2-status-check 会翻 ALARM 发 SNS 邮件），再 stop-instances 并等待 stopped
#   start = start-instances 并等待 running + 状态检查通过，再 enable-alarm-actions 恢复告警
#   实例按标签 Name=css-<env>-app 定位；不涉及 RDS / ALB / EIP（实例无 EIP，走 ALB 私网，重启后私网 IP 不变）
#   ⚠️ 停机期间该环境域名 5xx（ALB 无健康目标）；CI 对该分支的部署会因 SSM 不 Online 而失败——停机前先知会使用方
#   ⚠️ prod 需手输 prod 二次确认。terraform aws_instance 不管理运行状态，停机不产生 drift
set -euo pipefail
export MSYS_NO_PATHCONV=1 PYTHONUTF8=1

ACTION="${1:?用法: ec2-power.sh <stop|start|status> <env> [env ...]}"; shift
[ $# -ge 1 ] || { echo "至少给一个环境名"; exit 1; }
REGION="${AWS_REGION:-us-east-1}"
case "$ACTION" in stop|start|status) ;; *) echo "未知动作 $ACTION（stop|start|status）"; exit 1;; esac

for e in "$@"; do
  case "$e" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "未知环境 $e"; exit 1;; esac
done
if [ "$ACTION" != "status" ] && printf '%s\n' "$@" | grep -qx prod; then
  read -r -p "将对【prod】执行 $ACTION，请输入 prod 确认: " ans; [ "$ans" = "prod" ] || { echo "已取消"; exit 1; }
fi

lookup() {  # env -> instance id（唯一）
  local ids
  ids=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=css-$1-app" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text | tr -d '\r')
  [ -n "$ids" ] || { echo "[FAIL] 找不到 Name=css-$1-app 的实例"; exit 1; }
  [ "$(wc -w <<<"$ids")" -eq 1 ] || { echo "[FAIL] Name=css-$1-app 匹配多台: $ids"; exit 1; }
  echo "$ids"
}
show() {
  aws ec2 describe-instances --region "$REGION" --instance-ids "$@" \
    --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Id:InstanceId,State:State.Name,Type:InstanceType,IP:PrivateIpAddress}" --output table
}
alarms_of() {  # env -> 告警名列表（css-<env>-*）
  aws cloudwatch describe-alarms --region "$REGION" --alarm-name-prefix "css-$1-" \
    --query 'MetricAlarms[].AlarmName' --output text | tr -d '\r'
}

declare -A ID; IDS=""
for e in "$@"; do ID[$e]=$(lookup "$e"); IDS="$IDS ${ID[$e]}"; done
echo "== 当前状态"; show $IDS
[ "$ACTION" = "status" ] && exit 0

if [ "$ACTION" = "stop" ]; then
  for e in "$@"; do
    A=$(alarms_of "$e"); [ -n "$A" ] || continue
    echo "-- 关闭告警动作 [$e]: $(wc -w <<<"$A") 条"
    aws cloudwatch disable-alarm-actions --region "$REGION" --alarm-names $A
  done
  echo "-- stop-instances:$IDS"
  aws ec2 stop-instances --region "$REGION" --instance-ids $IDS --query 'StoppingInstances[].[InstanceId,CurrentState.Name]' --output text
  aws ec2 wait instance-stopped --region "$REGION" --instance-ids $IDS
else
  echo "-- start-instances:$IDS"
  aws ec2 start-instances --region "$REGION" --instance-ids $IDS --query 'StartingInstances[].[InstanceId,CurrentState.Name]' --output text
  aws ec2 wait instance-running --region "$REGION" --instance-ids $IDS
  echo "-- 等待实例状态检查通过（最长 ~10 分钟）"
  aws ec2 wait instance-status-ok --region "$REGION" --instance-ids $IDS
  for e in "$@"; do
    A=$(alarms_of "$e"); [ -n "$A" ] || continue
    echo "-- 恢复告警动作 [$e]: $(wc -w <<<"$A") 条"
    aws cloudwatch enable-alarm-actions --region "$REGION" --alarm-names $A
  done
fi
echo "== 完成后状态"; show $IDS
