#!/usr/bin/env bash
# CloudWatch 监控：告警（Alarms）+ 通知（SNS 邮件）+ 仪表盘（Dashboard）。
# 覆盖 EC2 应用机 / RDS / ALB 目标健康 三类关键指标，一个环境一套，资源带 Group+CssEnv 双标签。
#
# 成本（us-east-1）：告警 $0.10/个/月，本脚本每环境约 10 个 → ~$1；Dashboard 前 3 个免费；
#   SNS 邮件每月前 1000 封免费；基础指标（5 分钟粒度）免费。合计每环境约 $1/月。
#   ⚠️ EC2 内存/磁盘使用率**不是**基础指标——要监控得装 CloudWatch Agent 走自定义指标
#   （$0.30/指标/月），本脚本用 --with-agent 开启，默认不开。
#
# 用法: ./create-monitoring.sh <test|uat|prod> [告警邮箱] [--with-agent]
#   例: ./create-monitoring.sh test ops@example.com
#       ./create-monitoring.sh prod ops@example.com --with-agent
# 首次指定邮箱后，AWS 会发一封确认邮件，**必须点确认链接**订阅才生效。
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: create-monitoring.sh <test|uat|prod> [告警邮箱] [--with-agent]}"
EMAIL="${2:-}"
WITH_AGENT="${3:-}"
REGION="us-east-1"
case "$ENV_NAME" in
  test|uat) GROUP=css-non-prod; RDS_ID=css-non-prod ;;
  prod)     GROUP=css-prod;     RDS_ID=css-prod ;;
  *) echo "环境必须是 test|uat|prod"; exit 1 ;;
esac
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
TAGS="Key=Group,Value=$GROUP Key=CssEnv,Value=css-$ENV_NAME"

# ---- 目标资源 ----
INST=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=css-$ENV_NAME-app" \
  "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId')
ALB_ARN=$(awsq elbv2 describe-load-balancers --names "css-$ENV_NAME" --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
TG_ARN=$(awsq elbv2 describe-target-groups --names "css-$ENV_NAME-fe-tg" --query 'TargetGroups[0].TargetGroupArn' 2>/dev/null || echo None)
RDS_EXISTS=$(awsq rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].DBInstanceIdentifier' 2>/dev/null || echo None)
echo "监控目标: EC2=$INST  ALB=${ALB_ARN##*/}  TG=${TG_ARN##*/}  RDS=$RDS_EXISTS"

# ---- SNS 主题（告警送到哪）----
TOPIC_NAME="css-$ENV_NAME-alarms"
TOPIC_ARN=$(awsq sns create-topic --name "$TOPIC_NAME" --tags $TAGS --query 'TopicArn')
echo "SNS 主题: $TOPIC_ARN"
if [ -n "$EMAIL" ]; then
  EXIST=$(awsq sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
    --query "Subscriptions[?Endpoint=='$EMAIL'].SubscriptionArn")
  if [ -z "$EXIST" ] || [ "$EXIST" = "None" ]; then
    aws --region "$REGION" sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL" >/dev/null
    echo "已向 $EMAIL 发送订阅确认邮件——【必须点邮件里的确认链接】否则收不到告警"
  else
    echo "邮箱已订阅: $EMAIL"
  fi
fi

alarm() {  # 名字 描述 命名空间 指标 维度 统计 比较符 阈值 周期 连续次数 [缺失数据处理]
  local name=$1 desc=$2 ns=$3 metric=$4 dims=$5 stat=$6 op=$7 th=$8 period=$9 evals=${10} missing=${11:-notBreaching}
  aws --region "$REGION" cloudwatch put-metric-alarm \
    --alarm-name "$name" --alarm-description "$desc" \
    --namespace "$ns" --metric-name "$metric" --dimensions $dims \
    --statistic "$stat" --comparison-operator "$op" --threshold "$th" \
    --period "$period" --evaluation-periods "$evals" --treat-missing-data "$missing" \
    --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" \
    --tags $TAGS >/dev/null
  echo "  告警: $name"
}

echo "===== 创建告警 ====="
if [ "$INST" != "None" ] && [ -n "$INST" ]; then
  # CPU 持续高 = 可能有死循环/负载过大；状态检查失败 = 机器或底层硬件出问题
  alarm "css-$ENV_NAME-ec2-cpu-high" "应用机 CPU 连续 15 分钟 >80%" \
    AWS/EC2 CPUUtilization "Name=InstanceId,Value=$INST" Average GreaterThanThreshold 80 300 3
  alarm "css-$ENV_NAME-ec2-status-check" "应用机状态检查失败（实例或宿主机异常）" \
    AWS/EC2 StatusCheckFailed "Name=InstanceId,Value=$INST" Maximum GreaterThanThreshold 0 300 2 breaching
  # EBS 剩余空间没有基础指标，只能靠 Agent；这里放一条 CPU 积分告警（t 系列突发型才有意义）
  case "$(awsq ec2 describe-instances --instance-ids "$INST" --query 'Reservations[0].Instances[0].InstanceType')" in
    t2.*|t3.*|t4g.*)
      alarm "css-$ENV_NAME-ec2-cpu-credit-low" "CPU 积分即将耗尽（突发型实例会被限速）" \
        AWS/EC2 CPUCreditBalance "Name=InstanceId,Value=$INST" Average LessThanThreshold 20 300 3 ;;
  esac
fi

if [ "$RDS_EXISTS" != "None" ]; then
  # 内存是本实例的真实瓶颈（实测 t4g.micro 只剩 ~146MB 可用），阈值按 1GB 机型定 100MB
  alarm "css-$ENV_NAME-rds-cpu-high" "数据库 CPU 连续 15 分钟 >80%" \
    AWS/RDS CPUUtilization "Name=DBInstanceIdentifier,Value=$RDS_ID" Average GreaterThanThreshold 80 300 3
  alarm "css-$ENV_NAME-rds-memory-low" "数据库可用内存 <100MB（换页会让查询雪崩）" \
    AWS/RDS FreeableMemory "Name=DBInstanceIdentifier,Value=$RDS_ID" Average LessThanThreshold 104857600 300 3
  alarm "css-$ENV_NAME-rds-storage-low" "数据库剩余存储 <2GB" \
    AWS/RDS FreeStorageSpace "Name=DBInstanceIdentifier,Value=$RDS_ID" Average LessThanThreshold 2147483648 300 2
  alarm "css-$ENV_NAME-rds-connections-high" "数据库连接数 >80（t4g.micro 上限约 100）" \
    AWS/RDS DatabaseConnections "Name=DBInstanceIdentifier,Value=$RDS_ID" Average GreaterThanThreshold 80 300 3
fi

if [ "$ALB_ARN" != "None" ] && [ "$TG_ARN" != "None" ]; then
  LB_DIM="app/${ALB_ARN#*loadbalancer/app/}"
  TG_DIM="targetgroup/${TG_ARN#*targetgroup/}"
  # 健康目标数 <1 = 服务实际已不可用（比 5xx 更早、更确定）
  alarm "css-$ENV_NAME-alb-no-healthy-target" "ALB 后面没有健康目标——服务不可用" \
    AWS/ApplicationELB HealthyHostCount "Name=TargetGroup,Value=$TG_DIM Name=LoadBalancer,Value=$LB_DIM" \
    Average LessThanThreshold 1 60 3 breaching
  alarm "css-$ENV_NAME-alb-5xx" "ALB 5 分钟内后端 5xx >10 次" \
    AWS/ApplicationELB HTTPCode_Target_5XX_Count "Name=LoadBalancer,Value=$LB_DIM" \
    Sum GreaterThanThreshold 10 300 1
  alarm "css-$ENV_NAME-alb-latency-high" "后端响应 P95 >3 秒" \
    AWS/ApplicationELB TargetResponseTime "Name=LoadBalancer,Value=$LB_DIM" \
    Average GreaterThanThreshold 3 300 3
fi

# ---- Dashboard（一屏看完该环境）----
DASH="css-$ENV_NAME"
BODY=$( (python3 - "$ENV_NAME" "$INST" "$RDS_ID" "${ALB_ARN:-None}" "${TG_ARN:-None}" 2>/dev/null \
      || python - "$ENV_NAME" "$INST" "$RDS_ID" "${ALB_ARN:-None}" "${TG_ARN:-None}") <<'PY'
import json, sys
env, inst, rds, alb, tg = sys.argv[1:6]
w, widgets, y = 12, [], 0
def add(title, metrics, region='us-east-1'):
    global y
    widgets.append({"type":"metric","x":0 if len(widgets)%2==0 else 12,"y":y,"width":w,"height":6,
                    "properties":{"title":title,"region":region,"metrics":metrics,"stat":"Average","period":300}})
    if len(widgets)%2==0: y += 6
if inst and inst!='None':
    add("应用机 CPU %", [["AWS/EC2","CPUUtilization","InstanceId",inst]])
    add("应用机 网络流量", [["AWS/EC2","NetworkIn","InstanceId",inst],[".","NetworkOut",".","."]])
if rds and rds!='None':
    add("数据库 CPU %", [["AWS/RDS","CPUUtilization","DBInstanceIdentifier",rds]])
    add("数据库 可用内存/连接数", [["AWS/RDS","FreeableMemory","DBInstanceIdentifier",rds],
                                   [".","DatabaseConnections",".","."]])
if alb!='None' and tg!='None':
    lb = "app/" + alb.split("loadbalancer/app/")[1]
    tgd = "targetgroup/" + tg.split("targetgroup/")[1]
    add("ALB 请求数/5xx", [["AWS/ApplicationELB","RequestCount","LoadBalancer",lb],
                            [".","HTTPCode_Target_5XX_Count",".","."]])
    add("ALB 健康目标数/响应时间", [["AWS/ApplicationELB","HealthyHostCount","TargetGroup",tgd,"LoadBalancer",lb],
                                     [".","TargetResponseTime","LoadBalancer",lb]])
print(json.dumps({"widgets": widgets}))
PY
)
aws --region "$REGION" cloudwatch put-dashboard --dashboard-name "$DASH" --dashboard-body "$BODY" >/dev/null
echo "Dashboard: $DASH"

# ---- 可选：CloudWatch Agent（内存/磁盘等系统级指标，基础指标里没有）----
if [ "$WITH_AGENT" = "--with-agent" ] && [ "$INST" != "None" ]; then
  echo "===== 安装 CloudWatch Agent（内存/磁盘自定义指标，约 +\$1.2/月/机）====="
  CFG='{"metrics":{"namespace":"CSS/'"$ENV_NAME"'","append_dimensions":{"InstanceId":"${aws:InstanceId}"},
    "metrics_collected":{"mem":{"measurement":[{"name":"mem_used_percent","rename":"MemUsedPercent"}],"metrics_collection_interval":300},
    "disk":{"resources":["/"],"measurement":[{"name":"used_percent","rename":"DiskUsedPercent"}],"metrics_collection_interval":300}}}}'
  B64=$( (python3 -c "import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())" "$CFG" 2>/dev/null \
        || python -c "import base64,sys;print(base64.b64encode(sys.argv[1].encode()).decode())" "$CFG") )
  CMD="dnf install -y amazon-cloudwatch-agent >/dev/null 2>&1 || yum install -y amazon-cloudwatch-agent >/dev/null 2>&1
echo $B64 | base64 -d > /opt/aws/amazon-cloudwatch-agent/etc/cw.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw.json
systemctl enable amazon-cloudwatch-agent; systemctl is-active amazon-cloudwatch-agent"
  PARAMS=$( (python3 - "$CMD" 2>/dev/null || python - "$CMD") <<'PY'
import json, sys
print(json.dumps({"commands": [sys.argv[1]], "executionTimeout": ["900"]}))
PY
)
  CID=$(awsq ssm send-command --instance-ids "$INST" --document-name AWS-RunShellScript \
    --comment "install cloudwatch agent" --parameters "$PARAMS" --query 'Command.CommandId')
  for i in $(seq 1 36); do
    ST=$(awsq ssm get-command-invocation --command-id "$CID" --instance-id "$INST" --query Status 2>/dev/null || echo Pending)
    case "$ST" in Success|Failed|TimedOut) break ;; esac; sleep 5
  done
  echo "Agent 安装: $ST"
  echo "[提醒] 实例角色 css-ec2-$ENV_NAME 需要 CloudWatchAgentServerPolicy 才能写指标——脚本已在 07-iam 附加"
  alarm "css-$ENV_NAME-ec2-mem-high" "应用机内存使用率 >85%" \
    "CSS/$ENV_NAME" MemUsedPercent "Name=InstanceId,Value=$INST" Average GreaterThanThreshold 85 300 3
  alarm "css-$ENV_NAME-ec2-disk-high" "应用机根分区使用率 >85%" \
    "CSS/$ENV_NAME" DiskUsedPercent "Name=InstanceId,Value=$INST" Average GreaterThanThreshold 85 300 2
fi

echo ""
echo "===== $ENV_NAME 环境监控就绪 ====="
echo "告警列表: https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#alarmsV2:"
echo "仪表盘:   https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards/dashboard/$DASH"
[ -n "$EMAIL" ] && echo "⚠️ 记得去 $EMAIL 邮箱点确认链接，否则告警发不出来"
