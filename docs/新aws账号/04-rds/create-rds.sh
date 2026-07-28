#!/usr/bin/env bash
# 创建两个 RDS PostgreSQL 实例（各自 VPC 的私有子网，不可公网访问，主密码 Secrets Manager 托管）。
#   nonprod → 实例 css-non-prod（2026-07-28 起：旧默认 VPC 同名实例已删除，本实例接替其名）
#   prod    → 实例 css-prod（Multi-AZ + 备份 7 天 + 删除保护）
# ⚠️ 计费资源：账号需已升级 Paid plan。用法: ./create-rds.sh <nonprod|prod>
set -euo pipefail

GROUP="${1:?用法: create-rds.sh <nonprod|prod>}"
REGION="us-east-1"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

case "$GROUP" in
  nonprod) VPC_NAME=css-non-prod; DB_ID=css-non-prod; CLASS=db.t4g.micro
           MULTI_AZ=""; RETENTION=1; PROTECT="--no-deletion-protection"; SG_NAME=css-nonprod-rds-sg ;;
  prod)    VPC_NAME=css-prod;     DB_ID=css-prod;       CLASS=db.t4g.medium
           MULTI_AZ="--multi-az"; RETENTION=7; PROTECT="--deletion-protection"; SG_NAME=css-prod-rds-sg ;;
  *) echo "未知组"; exit 1 ;;
esac
case "$GROUP" in prod) EXTRA_TAGS='Key=CssEnv,Value=css-prod' ;; *) EXTRA_TAGS="" ;; esac

VPC_ID=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query 'Vpcs[0].VpcId')
PRI1=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-private-1a" --query 'Subnets[0].SubnetId')
PRI2=$(awsq ec2 describe-subnets --filters "Name=tag:Name,Values=$VPC_NAME-private-1b" --query 'Subnets[0].SubnetId')
SG=$(awsq ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
[ "$VPC_ID" != "None" ] || { echo "VPC $VPC_NAME 不存在，先跑 01-vpc"; exit 1; }

SUBNET_GROUP="$VPC_NAME-db-subnets"
if ! aws --region "$REGION" rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" >/dev/null 2>&1; then
  aws --region "$REGION" rds create-db-subnet-group \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --db-subnet-group-description "$VPC_NAME private subnets" \
    --subnet-ids "$PRI1" "$PRI2" \
    --tags Key=Group,Value="$VPC_NAME" >/dev/null
  echo "子网组创建: $SUBNET_GROUP"
fi

if aws --region "$REGION" rds describe-db-instances --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  echo "RDS 实例已存在: $DB_ID"
else
  # 运行时取最新 PG16 小版本（与现有 css-non-prod 16.14 同大版本，避免固定小版本被下架）
  PG_VER=$(awsq rds describe-db-engine-versions --engine postgres \
    --query "DBEngineVersions[?starts_with(EngineVersion,'16.')].EngineVersion | [-1]")
  echo "使用引擎版本: postgres $PG_VER"
  # shellcheck disable=SC2086
  aws --region "$REGION" rds create-db-instance \
    --db-instance-identifier "$DB_ID" \
    --engine postgres --engine-version "$PG_VER" \
    --db-instance-class "$CLASS" \
    --allocated-storage 20 --max-allocated-storage 100 --storage-type gp3 \
    --master-username postgres --manage-master-user-password \
    --db-subnet-group-name "$SUBNET_GROUP" \
    --vpc-security-group-ids "$SG" \
    --no-publicly-accessible \
    --backup-retention-period "$RETENTION" \
    --storage-encrypted \
    $MULTI_AZ $PROTECT \
    --tags Key=Group,Value="$VPC_NAME" $EXTRA_TAGS >/dev/null
  echo "RDS 创建中: $DB_ID（$CLASS，约 10-15 分钟可用）"
  echo "主密码在 Secrets Manager（rds! 前缀的托管 secret）"
fi
echo "就绪后建库: 见 ../05-数据同步/create-databases.sh"
