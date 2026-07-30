#!/usr/bin/env bash
# 创建网络入口机（⚠️ 计费资源：需 Paid plan）：
#   nonprod → 网关机 css-non-prod-gw（t4g.micro+EIP，两件事：堡垒 22 / NAT 出网），
#             并把私有路由表默认路由指向本机 ENI；
#             （2026-07-29 起不再装 nginx 反代——Web 一律走 ALB，见 12-alb）
#   prod    → 堡垒机 css-prod-bastion（t4g.micro+EIP，纯 SSH 跳板）+ 托管 NAT 网关 + 私有路由。
# 用法: ./create-gateway.sh <nonprod|prod> [ssh-keypair名]
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"  # git-bash: 防 /aws/... 参数被误转成 Windows 路径

GROUP="${1:?用法: create-gateway.sh <nonprod|prod> [keypair]}"
KEYPAIR="${2:-}"
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

case "$GROUP" in
  nonprod) VPC_NAME=css-non-prod; NAME=css-non-prod-gw;    SG_NAME=css-non-prod-gw-sg ;;
  prod)    VPC_NAME=css-prod;     NAME=css-prod-bastion;  SG_NAME=css-prod-bastion-sg ;;
  *) echo "未知组"; exit 1 ;;
esac

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
PUB1=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-public-1a" --query 'Subnets[0].SubnetId')
SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
PRI_RT=$(awsq ec2 describe-route-tables --filters "Name=tag:Name,Values=$VPC_NAME-private-rt" --query 'RouteTables[0].RouteTableId')
AMI_ARM=$(awsq ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 --query 'Parameter.Value')
KEYARG=(); [ -n "$KEYPAIR" ] && KEYARG=(--key-name "$KEYPAIR")

EXIST=$(awsq ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[0].Instances[0].InstanceId')

if [ "$GROUP" = "nonprod" ]; then
  # ---- 网关机：NAT(iptables) + 堡垒（Web 反代已退役，ALB 接管）----
  USERDATA=$(cat <<'EOF'
#!/bin/bash
set -e
# NAT（规则用独立 systemd 单元开机重放，不依赖 iptables-services 的持久化，AL2023 更稳）
echo net.ipv4.ip_forward=1 > /etc/sysctl.d/99-nat.conf
sysctl -p /etc/sysctl.d/99-nat.conf
dnf install -y iptables-nft || dnf install -y iptables
cat > /usr/local/bin/css-nat.sh <<'NAT'
#!/usr/bin/env bash
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
iptables -t nat -C POSTROUTING -o "$IFACE" -s 10.20.0.0/16 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -o "$IFACE" -s 10.20.0.0/16 -j MASQUERADE
iptables -C FORWARD -s 10.20.0.0/16 -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD -s 10.20.0.0/16 -j ACCEPT
iptables -C FORWARD -d 10.20.0.0/16 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -I FORWARD -d 10.20.0.0/16 -m state --state RELATED,ESTABLISHED -j ACCEPT
NAT
chmod +x /usr/local/bin/css-nat.sh
cat > /etc/systemd/system/css-nat.service <<'SVC'
[Unit]
Description=CSS non-prod NAT masquerade rules
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/css-nat.sh
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now css-nat.service
EOF
)
  if [ "$EXIST" != "None" ]; then
    ID="$EXIST"; echo "网关机已存在: $ID"
  else
    ID=$(awsq ec2 run-instances \
      --image-id "$AMI_ARM" --instance-type t4g.micro \
      --subnet-id "$PUB1" --security-group-ids "$SG" "${KEYARG[@]}" \
      --associate-public-ip-address \
      --user-data "$USERDATA" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Group,Value=$VPC_NAME},{Key=CssEnv,Value=css-shared}]" \
      --query 'Instances[0].InstanceId')
    echo "网关机创建: $ID (t4g.micro)"
    aws --region "$REGION" ec2 wait instance-running --instance-ids "$ID"
  fi
  # NAT 需要关 source/dest check
  aws --region "$REGION" ec2 modify-instance-attribute --instance-id "$ID" --no-source-dest-check
  # 私有路由表默认路由 → 网关机 ENI
  ENI=$(awsq ec2 describe-instances --instance-ids "$ID" --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId')
  aws --region "$REGION" ec2 create-route --route-table-id "$PRI_RT" --destination-cidr-block 0.0.0.0/0 --network-interface-id "$ENI" >/dev/null 2>&1 \
    || aws --region "$REGION" ec2 replace-route --route-table-id "$PRI_RT" --destination-cidr-block 0.0.0.0/0 --network-interface-id "$ENI"
  echo "私有子网默认路由 → $ENI"
else
  # ---- prod：纯堡垒机 + 托管 NAT 网关 ----
  if [ "$EXIST" != "None" ]; then
    ID="$EXIST"; echo "堡垒机已存在: $ID"
  else
    ID=$(awsq ec2 run-instances \
      --image-id "$AMI_ARM" --instance-type t4g.micro \
      --subnet-id "$PUB1" --security-group-ids "$SG" "${KEYARG[@]}" \
      --associate-public-ip-address \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Group,Value=$VPC_NAME},{Key=CssEnv,Value=css-shared}]" \
      --query 'Instances[0].InstanceId')
    echo "堡垒机创建: $ID (t4g.micro)"
  fi
  NAT=$(awsq ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,available" --query 'NatGateways[0].NatGatewayId')
  if [ "$NAT" = "None" ]; then
    ALLOC=$(awsq ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$VPC_NAME-nat-eip},{Key=Group,Value=$VPC_NAME},{Key=CssEnv,Value=css-shared}]" --query 'AllocationId')
    NAT=$(awsq ec2 create-nat-gateway --subnet-id "$PUB1" --allocation-id "$ALLOC" \
      --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=$VPC_NAME-nat},{Key=Group,Value=$VPC_NAME},{Key=CssEnv,Value=css-shared}]" \
      --query 'NatGateway.NatGatewayId')
    echo "NAT 网关创建中: $NAT"
    aws --region "$REGION" ec2 wait nat-gateway-available --nat-gateway-ids "$NAT"
  fi
  aws --region "$REGION" ec2 create-route --route-table-id "$PRI_RT" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT" >/dev/null 2>&1 \
    || aws --region "$REGION" ec2 replace-route --route-table-id "$PRI_RT" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT"
  echo "私有子网默认路由 → $NAT"
fi

# ---- SSM 运维 profile（Run Command/Session Manager 通道；附读 dbsync 中转桶 + RDS 托管密码，
#      供 05-数据同步/restore-dump-via-gw.sh 在本机恢复数据库用。CssEnv 一律 css-shared——
#      **绝不能打 css-test/css-uat**，否则这台机器会被部署命令当成应用机选中）----
ACCOUNT_ID=$(awsq sts get-caller-identity --query Account)
# 角色名跟 VPC/安全组一样用带连字符的写法：css-gw-non-prod / css-gw-prod（2026-07-29 统一）
GW_ROLE="css-gw-${VPC_NAME#css-}"
OLD_GW_ROLE="css-gw-$GROUP"          # 改名前的旧名（css-gw-nonprod），下面自动迁移并清理
if ! aws iam get-role --role-name "$GW_ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$GW_ROLE" --tags Key=Group,Value="$VPC_NAME" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  echo "角色创建: $GW_ROLE"
fi
aws iam attach-role-policy --role-name "$GW_ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam put-role-policy --role-name "$GW_ROLE" --policy-name "$GW_ROLE-ops" --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    { \"Sid\": \"DbsyncBucket\", \"Effect\": \"Allow\",
      \"Action\": [\"s3:GetObject\",\"s3:ListBucket\"],
      \"Resource\": [\"arn:aws:s3:::css-dbsync-$ACCOUNT_ID\",\"arn:aws:s3:::css-dbsync-$ACCOUNT_ID/*\"] },
    { \"Sid\": \"RdsManagedSecret\", \"Effect\": \"Allow\",
      \"Action\": \"secretsmanager:GetSecretValue\",
      \"Resource\": \"arn:aws:secretsmanager:$REGION:$ACCOUNT_ID:secret:rds!*\" }
  ]
}"
if ! aws iam get-instance-profile --instance-profile-name "$GW_ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$GW_ROLE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$GW_ROLE" --role-name "$GW_ROLE"
  echo "实例 profile 创建: $GW_ROLE"
  sleep 10   # IAM 最终一致：新 profile 立刻 associate 会报 InvalidParameterValue
fi
# ---- 旧名角色迁移（css-gw-nonprod → css-gw-non-prod）：IAM 角色名不可改，只能新建后换绑 ----
if [ "$OLD_GW_ROLE" != "$GW_ROLE" ] && aws iam get-instance-profile --instance-profile-name "$OLD_GW_ROLE" >/dev/null 2>&1; then
  CUR=$(awsq ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$ID"     --query 'IamInstanceProfileAssociations[?State==`associated`]|[0].IamInstanceProfile.Arn')
  case "$CUR" in
    */"$OLD_GW_ROLE")
      A=$(awsq ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$ID"         --query 'IamInstanceProfileAssociations[?State==`associated`]|[0].AssociationId')
      aws --region "$REGION" ec2 replace-iam-instance-profile-association         --association-id "$A" --iam-instance-profile "Name=$GW_ROLE" >/dev/null
      echo "实例 profile 已从 $OLD_GW_ROLE 换成 $GW_ROLE（SSM agent 数分钟内自动用上新凭证）"
      ;;
  esac
  # 旧 profile/角色清理（换绑后即无使用者）
  aws iam remove-role-from-instance-profile --instance-profile-name "$OLD_GW_ROLE" --role-name "$OLD_GW_ROLE" 2>/dev/null || true
  aws iam delete-instance-profile --instance-profile-name "$OLD_GW_ROLE" 2>/dev/null && echo "已删旧 profile: $OLD_GW_ROLE" || true
  aws iam delete-role-policy --role-name "$OLD_GW_ROLE" --policy-name "$OLD_GW_ROLE-ops" 2>/dev/null || true
  aws iam detach-role-policy --role-name "$OLD_GW_ROLE" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
  aws iam delete-role --role-name "$OLD_GW_ROLE" 2>/dev/null && echo "已删旧角色: $OLD_GW_ROLE" || true
fi

ASSOC=$(awsq ec2 describe-iam-instance-profile-associations --filters "Name=instance-id,Values=$ID" --query 'IamInstanceProfileAssociations[?State==`associated`]|[0].AssociationId')
if [ "$ASSOC" = "None" ] || [ -z "$ASSOC" ]; then
  for i in 1 2 3; do
    aws --region "$REGION" ec2 associate-iam-instance-profile --instance-id "$ID" \
      --iam-instance-profile "Name=$GW_ROLE" >/dev/null && break || sleep 15
  done
  echo "实例 profile 挂载: $GW_ROLE → $ID"
else
  echo "实例 profile 已挂载: $GW_ROLE"
fi

# ---- EIP 绑定（网关/堡垒机固定公网入口）----
EIP_ALLOC=$(awsq ec2 describe-addresses --filters "Name=tag:Name,Values=$NAME-eip" --query 'Addresses[0].AllocationId')
if [ "$EIP_ALLOC" = "None" ]; then
  EIP_ALLOC=$(awsq ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$NAME-eip},{Key=Group,Value=$VPC_NAME},{Key=CssEnv,Value=css-shared}]" --query 'AllocationId')
fi
aws --region "$REGION" ec2 associate-address --instance-id "$ID" --allocation-id "$EIP_ALLOC" --allow-reassociation >/dev/null
EIP=$(awsq ec2 describe-addresses --allocation-ids "$EIP_ALLOC" --query 'Addresses[0].PublicIp')
echo "===== $NAME 就绪，EIP: $EIP ====="
[ "$GROUP" = "nonprod" ] && echo "SSH 跳板: ssh -i ~/.ssh/css-non-prod-gw.pem -J ec2-user@$EIP ec2-user@<私网IP>（Web 走各环境 ALB，不再经本机反代）"
