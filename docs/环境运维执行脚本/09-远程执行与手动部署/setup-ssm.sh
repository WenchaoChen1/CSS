#!/usr/bin/env bash
# 把一台 EC2 配置成 SSM Run Command 可达的部署目标（挂实例角色 + 打 Environment 标签 + 验证 Online）。
# CI/CD 的部署命令就是经 SSM 送达（免 SSH/22/pem）；用 docs/环境运维执行脚本/06-服务器密钥与访问 建的新机已自动配好，
# 本脚本用于：给已有机器补配（如现有 test 机）、或排查一台机器为什么 SSM 不可达。
# 用法: ./setup-ssm.sh <test|uat|prod> <instance-id>
set -euo pipefail

ENV_NAME="${1:?用法: setup-ssm.sh <test|uat|prod> <instance-id>}"
INSTANCE="${2:?缺 instance-id（如 i-08e110b5a5425980d）}"
REGION="us-east-1"
case "$ENV_NAME" in test|uat|prod) ;; *) echo "环境必须是 test|uat|prod"; exit 1 ;; esac
case "$ENV_NAME" in prod) GROUP=css-prod ;; *) GROUP=css-non-prod ;; esac
PROFILE="css-ec2-$ENV_NAME"

# ---- 1) 实例角色：无关联则挂 css-ec2-<env>；已有其他角色则提示（避免破坏既有权限）----
ASSOC=$(aws ec2 describe-iam-instance-profile-associations --region "$REGION" \
  --filters "Name=instance-id,Values=$INSTANCE" \
  --query 'IamInstanceProfileAssociations[0].IamInstanceProfile.Arn' --output text | tr -d '\r')
if [ "$ASSOC" = "None" ] || [ -z "$ASSOC" ]; then
  aws ec2 associate-iam-instance-profile --region "$REGION" \
    --instance-id "$INSTANCE" --iam-instance-profile Name="$PROFILE" >/dev/null
  echo "实例角色已挂: $PROFILE"
elif [[ "$ASSOC" == *"/$PROFILE" ]]; then
  echo "实例角色已是: $PROFILE"
else
  PROFILE_NAME="${ASSOC##*/}"
  ROLE_NAME=$(aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" \
    --query 'InstanceProfile.Roles[0].RoleName' --output text | tr -d '\r')
  echo "⚠️ 实例已挂其他 profile: $PROFILE_NAME（角色 $ROLE_NAME）—— 不替换，改为给该角色补 SSM+参数权限"
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
  aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "css-$ENV_NAME-params-transition" \
    --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ssm:GetParameter\",\"ssm:GetParameters\"],\"Resource\":\"arn:aws:ssm:$REGION:582797602427:parameter/css/$ENV_NAME/*\"}]}"
  echo "已给 $ROLE_NAME 补挂 AmazonSSMManagedInstanceCore + /css/$ENV_NAME/* 读取"
fi

# ---- 2) 标签（SSM 按 Environment 定位部署目标；IAM 条件也校验它）----
aws ec2 create-tags --region "$REGION" --resources "$INSTANCE" \
  --tags "Key=Environment,Value=css-$ENV_NAME" "Key=EnvironmentGroup,Value=$GROUP"
echo "标签已打: Environment=css-$ENV_NAME EnvironmentGroup=$GROUP"

# ---- 3) 等待并验证 SSM Online（角色变更后 Agent 最长几分钟才刷新凭证）----
echo "等待 SSM Online（最长 5 分钟）..."
for i in $(seq 1 30); do
  PING=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE" \
    --query 'InstanceInformationList[0].PingStatus' --output text | tr -d '\r')
  [ "$PING" = "Online" ] && { echo "✅ SSM Online，部署链路可达"; exit 0; }
  sleep 10
done
echo "❌ 仍未 Online。排查：实例能否出站(NAT/公网)、SSM Agent 是否运行、角色是否生效（重启实例可强制刷新）"
exit 1
