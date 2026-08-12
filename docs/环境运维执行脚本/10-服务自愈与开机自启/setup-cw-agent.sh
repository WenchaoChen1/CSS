#!/usr/bin/env bash
# 在应用机上安装并配置 CloudWatch Agent，上报【磁盘 / 内存】使用率。
#
# 为什么必须装它（2026-08-05 事故教训）：
#   EC2 的原生 CloudWatch 指标由 hypervisor 采集——CPU、网络、磁盘 IO 它看得见，
#   但"客户机内部还剩多少磁盘 / 多少内存"看不见，那是操作系统内部的事。
#   结果：test 机 50GB 根卷被 docker 镜像撑到 98%，CI 的 migrate 死在
#   `no space left on device`，而**当时一条告警都没有**——最典型的"本可提前发现"的故障。
#   装完 Agent，css-terraform 的 monitoring stack 才能开 ec2-disk-high(>80%) / ec2-mem-high(>85%)。
#
# 上报什么（刻意只挑这两个，不贪）：
#   · disk_used_percent（挂载点 /，即根卷）→ 撑满会让部署失败、容器写不了日志
#   · mem_used_percent → 应用机 13+ 容器，内存吃紧时表现为容器被 OOM kill
#   成本：自定义指标 $0.30/个/月 → 约 $0.6/月/机。
#
# 幂等：已装则只更新配置并重启；可反复执行。
# 用法: ./setup-cw-agent.sh <test|uat|support-ref|support-demo|support-sync|prod>
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "用法: $0 <test|uat|support-ref|support-demo|support-sync|prod>"; exit 1 ;; esac

echo "===== 安装/配置 CloudWatch Agent（$ENV_NAME）====="

# 采集间隔 60s：磁盘/内存这类容量指标不需要更细，粒度越细自定义指标费用越高（按指标数不按点数，
# 但 60s 已足够——告警是 2 个周期 = 10 分钟内发现）
#
# ⚠️ `drop_device: true` 不是可选优化，是告警能否工作的前提（2026-08-05 首次装完实测发现）：
# 默认 disk 指标带 4 个维度 path/InstanceId/device/fstype，而 CloudWatch 告警要求维度**完全匹配**——
# css-terraform 的 ec2-disk-high 只声明 InstanceId/path/fstype，不 drop 就永远 INSUFFICIENT_DATA。
# 修法选 drop 而不是往告警里补 device=nvme0n1p1，因为设备名随机型/换盘会变，一变告警就静默失效。
REMOTE='set -e
if ! rpm -q amazon-cloudwatch-agent >/dev/null 2>&1; then
  echo "--- 安装 amazon-cloudwatch-agent"
  dnf install -y amazon-cloudwatch-agent >/dev/null 2>&1 || yum install -y amazon-cloudwatch-agent >/dev/null 2>&1
else
  echo "--- 已安装，跳过安装步骤"
fi

echo "--- 写配置"
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CFG
{
  "agent": { "metrics_collection_interval": 60, "run_as_user": "root" },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "InstanceId": "\${aws:InstanceId}" },
    "metrics_collected": {
      "disk": {
        "resources": ["/"],
        "measurement": ["used_percent"],
        "drop_device": true,
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CFG

echo "--- 启动"
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json >/dev/null
systemctl enable amazon-cloudwatch-agent >/dev/null 2>&1 || true

echo "--- 状态"
systemctl is-active amazon-cloudwatch-agent || true
df -h / | tail -1
free -m | head -2 | tail -1'

bash ../09-远程执行与手动部署/run.sh "$ENV_NAME" "$REMOTE"

echo
echo "===== 完成 ====="
echo "指标要等约 5 分钟才出现在 CloudWatch（命名空间 CWAgent）。核对："
echo "  aws cloudwatch list-metrics --namespace CWAgent --query 'Metrics[?MetricName==\`disk_used_percent\`]'"
echo
echo "然后在 css-terraform 打开告警（默认关着，因为它依赖本脚本先跑）："
echo "  css-non-prod/$ENV_NAME/monitoring 里给 module 传 enable_agent_alarms = true 再 apply"
echo "  → 生成 css-$ENV_NAME-ec2-disk-high（>80%）与 css-$ENV_NAME-ec2-mem-high（>85%）"
