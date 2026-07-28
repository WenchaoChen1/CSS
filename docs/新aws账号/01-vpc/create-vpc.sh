#!/usr/bin/env bash
# 创建 CSS 环境群组的网络骨架（全部零成本资源：VPC/子网/IGW/路由表/S3端点/安全组）。
# 用法: ./create-vpc.sh <nonprod|prod>
# 幂等：按 Name tag 查找已有资源，存在即复用；重复执行安全。
# 拓扑约定见 docs/环境/aws-css-non-prod.md 与 aws-css-prod.md（css 库）。
set -euo pipefail

GROUP="${1:?用法: create-vpc.sh <nonprod|prod>}"
REGION="us-east-1"
ADMIN_CIDR="221.214.0.190/32"   # 唯一管理白名单 IP

case "$GROUP" in
  nonprod) VPC_NAME=css-non-prod; CIDR=10.20.0.0/16
           PUB1=10.20.0.0/24; PUB2=10.20.1.0/24; PRI1=10.20.10.0/24; PRI2=10.20.11.0/24 ;;
  prod)    VPC_NAME=css-prod;     CIDR=10.10.0.0/16
           PUB1=10.10.0.0/24; PUB2=10.10.1.0/24; PRI1=10.10.10.0/24; PRI2=10.10.11.0/24 ;;
  *) echo "未知组: $GROUP（nonprod|prod）"; exit 1 ;;
esac
AZ1="${REGION}a"; AZ2="${REGION}b"

awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

# ---------- VPC ----------
VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
  VPC_ID=$(awsq ec2 create-vpc --cidr-block "$CIDR" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME},{Key=Group,Value=$VPC_NAME}]" \
    --query 'Vpc.VpcId')
  aws --region "$REGION" ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
  echo "VPC 创建: $VPC_ID"
else
  echo "VPC 复用: $VPC_ID"
fi

# ---------- 子网 ----------
ensure_subnet() { # name cidr az
  local name=$1 cidr=$2 az=$3 sid
  sid=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$name" "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId')
  if [ "$sid" = "None" ] || [ -z "$sid" ]; then
    sid=$(awsq ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$az" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name},{Key=Group,Value=$VPC_NAME}]" --query 'Subnet.SubnetId')
    echo "子网创建: $name $sid" >&2
  else
    echo "子网复用: $name $sid" >&2
  fi
  echo "$sid"
}
PUB1_ID=$(ensure_subnet "$VPC_NAME-public-1a"  "$PUB1" "$AZ1")
PUB2_ID=$(ensure_subnet "$VPC_NAME-public-1b"  "$PUB2" "$AZ2")
PRI1_ID=$(ensure_subnet "$VPC_NAME-private-1a" "$PRI1" "$AZ1")
PRI2_ID=$(ensure_subnet "$VPC_NAME-private-1b" "$PRI2" "$AZ2")

# ---------- IGW ----------
IGW_ID=$(awsq ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[0].InternetGatewayId')
if [ "$IGW_ID" = "None" ] || [ -z "$IGW_ID" ]; then
  IGW_ID=$(awsq ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=$VPC_NAME-igw},{Key=Group,Value=$VPC_NAME}]" \
    --query 'InternetGateway.InternetGatewayId')
  aws --region "$REGION" ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  echo "IGW 创建并挂载: $IGW_ID"
else
  echo "IGW 复用: $IGW_ID"
fi

# ---------- 路由表 ----------
ensure_rt() { # name
  local name=$1 rtid
  rtid=$(awsq ec2 describe-route-tables --filters "Name=tag:Name,Values=$name" "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[0].RouteTableId')
  if [ "$rtid" = "None" ] || [ -z "$rtid" ]; then
    rtid=$(awsq ec2 create-route-table --vpc-id "$VPC_ID" \
      --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$name},{Key=Group,Value=$VPC_NAME}]" --query 'RouteTable.RouteTableId')
    echo "路由表创建: $name $rtid" >&2
  else
    echo "路由表复用: $name $rtid" >&2
  fi
  echo "$rtid"
}
PUB_RT=$(ensure_rt "$VPC_NAME-public-rt")
PRI_RT=$(ensure_rt "$VPC_NAME-private-rt")

aws --region "$REGION" ec2 create-route --route-table-id "$PUB_RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null 2>&1 \
  || echo "公有默认路由已存在"
# 私有路由表的 0.0.0.0/0 → NAT（网关机 ENI / NAT 网关）在计费资源创建阶段补

assoc() { # rt subnet
  aws --region "$REGION" ec2 associate-route-table --route-table-id "$1" --subnet-id "$2" >/dev/null 2>&1 || true
}
assoc "$PUB_RT" "$PUB1_ID"; assoc "$PUB_RT" "$PUB2_ID"
assoc "$PRI_RT" "$PRI1_ID"; assoc "$PRI_RT" "$PRI2_ID"

# ---------- S3 Gateway Endpoint（免费） ----------
EP_ID=$(awsq ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=com.amazonaws.$REGION.s3" --query 'VpcEndpoints[0].VpcEndpointId')
if [ "$EP_ID" = "None" ] || [ -z "$EP_ID" ]; then
  EP_ID=$(awsq ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name "com.amazonaws.$REGION.s3" \
    --route-table-ids "$PUB_RT" "$PRI_RT" \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$VPC_NAME-s3-ep},{Key=Group,Value=$VPC_NAME}]" \
    --query 'VpcEndpoint.VpcEndpointId')
  echo "S3 端点创建: $EP_ID"
else
  echo "S3 端点复用: $EP_ID"
fi

# ---------- 安全组 ----------
ensure_sg() { # name desc
  local name=$1 desc=$2 sgid
  sgid=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$name" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
  if [ "$sgid" = "None" ] || [ -z "$sgid" ]; then
    sgid=$(awsq ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" \
      --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name},{Key=Group,Value=$VPC_NAME}]" --query 'GroupId')
    echo "SG 创建: $name $sgid" >&2
  else
    echo "SG 复用: $name $sgid" >&2
  fi
  echo "$sgid"
}
allow_cidr() { # sg port cidr
  aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$1" --protocol tcp --port "$2" --cidr "$3" >/dev/null 2>&1 || true
}
allow_sg() { # sg port src-sg
  aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$1" --protocol tcp --port "$2" --source-group "$3" >/dev/null 2>&1 || true
}
allow_all_from_cidr() { # sg cidr（网关机做 NAT 需收私网全部回程流量）
  aws --region "$REGION" ec2 authorize-security-group-ingress --group-id "$1" --protocol -1 --cidr "$2" >/dev/null 2>&1 || true
}

if [ "$GROUP" = "nonprod" ]; then
  # 访问规范（2026-07-28 用户拍板）：SSH 一律只经堡垒机；系统（Web）一律只经 ALB+域名；RDS 仅内网。
  GW_SG=$(ensure_sg  css-nonprod-gw-sg  "gateway: bastion+NAT, admin IP only")
  ALB_SG=$(ensure_sg css-nonprod-alb-sg "non-prod ALB, public 80/443")
  APP_SG=$(ensure_sg css-nonprod-app-sg "test/uat app servers, private")
  RDS_SG=$(ensure_sg css-nonprod-rds-sg "non-prod RDS")
  allow_cidr "$GW_SG" 22   "$ADMIN_CIDR"
  allow_cidr "$GW_SG" 80   "$ADMIN_CIDR"   # 过渡：网关 nginx 反代 → test（12-alb 的 ALB+域名就绪后收掉本条与下条）
  allow_cidr "$GW_SG" 8080 "$ADMIN_CIDR"   # 过渡：网关 nginx 反代 → uat
  allow_all_from_cidr "$GW_SG" "$CIDR"     # NAT 回程
  allow_cidr "$ALB_SG" 80  0.0.0.0/0
  allow_cidr "$ALB_SG" 443 0.0.0.0/0
  allow_sg "$APP_SG" 80 "$ALB_SG"          # Web 流量只收 ALB
  allow_sg "$APP_SG" 80 "$GW_SG"           # 过渡：网关反代通道，ALB 就绪后收掉
  allow_sg "$APP_SG" 22 "$GW_SG"           # SSH 只收堡垒机
  allow_sg "$RDS_SG" 5432 "$APP_SG"
  allow_sg "$RDS_SG" 5432 "$GW_SG"
  SUMMARY_SGS="gw=$GW_SG alb=$ALB_SG app=$APP_SG rds=$RDS_SG"
else
  ALB_SG=$(ensure_sg css-prod-alb-sg     "prod ALB, public 80/443")
  BAS_SG=$(ensure_sg css-prod-bastion-sg "prod bastion, admin IP only")
  APP_SG=$(ensure_sg css-prod-app-sg     "prod app server, private")
  RDS_SG=$(ensure_sg css-prod-rds-sg     "prod RDS")
  allow_cidr "$ALB_SG" 80  0.0.0.0/0
  allow_cidr "$ALB_SG" 443 0.0.0.0/0
  allow_cidr "$BAS_SG" 22  "$ADMIN_CIDR"
  allow_sg "$APP_SG" 80 "$ALB_SG"
  allow_sg "$APP_SG" 22 "$BAS_SG"
  allow_sg "$RDS_SG" 5432 "$APP_SG"
  allow_sg "$RDS_SG" 5432 "$BAS_SG"
  SUMMARY_SGS="alb=$ALB_SG bastion=$BAS_SG app=$APP_SG rds=$RDS_SG"
fi

echo ""
echo "===== $VPC_NAME 骨架就绪 ====="
echo "VPC:      $VPC_ID ($CIDR)"
echo "公有子网: $PUB1_ID($AZ1) $PUB2_ID($AZ2)"
echo "私有子网: $PRI1_ID($AZ1) $PRI2_ID($AZ2)"
echo "IGW:      $IGW_ID  公有RT: $PUB_RT  私有RT: $PRI_RT  S3端点: $EP_ID"
echo "安全组:   $SUMMARY_SGS"
