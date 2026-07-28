#!/usr/bin/env bash
# 创建环境应用服务器（私有子网、无公网 IP、固定私网 IP、挂 css-ec2-<env> 实例角色，user-data 装 docker+compose）。
#   test → css-non-prod VPC private-1a 10.20.10.10（默认 m7i-flex.large：2vCPU/8GB，当前 plan 可用）
#   uat  → css-non-prod VPC private-1b 10.20.11.10（同上）
#   prod → css-prod     VPC private-1a 10.10.10.10（默认 c5.xlarge，可传第二参覆盖如 c5.large）
# 实例名固定含环境名：css-test-app / css-uat-app / css-prod-app。
# 固定私网 IP 供 ALB 目标组、网关机反代与 SSH 跳板直达。⚠️ 计费资源。
# 实例大小可后期改：停机 → modify-instance-attribute --instance-type → 开机（私网 IP/角色/标签不变）。
# 用法: ./create-app-ec2.sh <test|uat|prod> [instance-type] [keypair]
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"  # git-bash: 防 /aws/... 参数被误转成 Windows 路径

ENV_NAME="${1:?用法: create-app-ec2.sh <test|uat|prod> [instance-type] [keypair]}"
KEYPAIR="${3:-wenchao}"     # 默认用本机 wenchao 密钥（先跑 ./setup-ssh-key.sh 导入）
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

case "$ENV_NAME" in
  test) VPC_NAME=css-non-prod; SUBNET_NAME=css-non-prod-private-1a; PRIVATE_IP=10.20.10.10
        TYPE="${2:-m7i-flex.large}"; SG_NAME=css-nonprod-app-sg ;;
  uat)  VPC_NAME=css-non-prod; SUBNET_NAME=css-non-prod-private-1b; PRIVATE_IP=10.20.11.10
        TYPE="${2:-m7i-flex.large}"; SG_NAME=css-nonprod-app-sg ;;
  prod) VPC_NAME=css-prod;     SUBNET_NAME=css-prod-private-1a;     PRIVATE_IP=10.10.10.10
        TYPE="${2:-c5.xlarge}"; SG_NAME=css-prod-app-sg ;;
  *) echo "环境必须是 test|uat|prod"; exit 1 ;;
esac
NAME="css-$ENV_NAME-app"
KEYARG=()
if aws --region "$REGION" ec2 describe-key-pairs --key-names "$KEYPAIR" >/dev/null 2>&1; then
  KEYARG=(--key-name "$KEYPAIR"); echo "使用 key pair: $KEYPAIR"
else
  echo "⚠️ key pair $KEYPAIR 不存在（先跑 ./setup-ssh-key.sh ~/.ssh/$KEYPAIR.pub），本机将只能经 SSM 登录"
fi

EXIST=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[0].Instances[0].InstanceId')
[ "$EXIST" = "None" ] || { echo "实例已存在: $NAME $EXIST"; exit 0; }

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
SUBNET=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$SUBNET_NAME" --query 'Subnets[0].SubnetId')
SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
AMI=$(awsq ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameter.Value')

USERDATA=$(cat <<'EOF'
#!/bin/bash
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
ARCH=$(uname -m); [ "$ARCH" = aarch64 ] && A=aarch64 || A=x86_64
curl -sL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$A" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
mkdir -p /opt/css
chown ec2-user:ec2-user /opt/css
EOF
)

ID=$(awsq ec2 run-instances \
  --image-id "$AMI" --instance-type "$TYPE" \
  --subnet-id "$SUBNET" --private-ip-address "$PRIVATE_IP" \
  --security-group-ids "$SG" "${KEYARG[@]}" \
  --iam-instance-profile Name="css-ec2-$ENV_NAME" \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=50,VolumeType=gp3,DeleteOnTermination=true}' \
  --no-associate-public-ip-address \
  --user-data "$USERDATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=CssEnv,Value=css-$ENV_NAME},{Key=Group,Value=$VPC_NAME}]" \
  --query 'Instances[0].InstanceId')
echo "实例创建: $NAME $ID ($TYPE, $PRIVATE_IP, 无公网 IP)"
echo "SSH: ssh -J ec2-user@<网关/堡垒EIP> ec2-user@$PRIVATE_IP"
echo "CI/CD 经 SSM 按标签 CssEnv=css-$ENV_NAME 定位本机"
