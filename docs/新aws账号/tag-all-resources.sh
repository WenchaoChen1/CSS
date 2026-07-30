#!/usr/bin/env bash
# 给新账号里【已存在】的资源统一补打两个标签（用户 2026-07-29 要求：所有资源都要有 Group + CssEnv）：
#   Group  = css-non-prod | css-prod        （成本/权限分组）
#   CssEnv = css-test | css-uat | css-prod  （环境专属资源）
#            css-shared                      （跨环境共享资源：VPC/子网/路由/SG/网关机/非生产 RDS 等）
#
# ⚠️ 为什么共享资源不能随便打 css-test/css-uat：
#    IAM 与部署脚本用 `CssEnv=css-<env>` 精确定位【部署目标机】（ssm:SendCommand 的条件、run.sh 的过滤）。
#    给网关机或 VPC 打上 css-test，会让它们被 test 的部署命令选中 → 往错误的机器上发部署。
#    因此共享资源统一用 css-shared，既满足"每个资源都有两个标签"，又不会被任何环境的部署逻辑命中。
#
# 幂集：重复执行安全（create-tags 是覆盖式）。用法: ./tag-all-resources.sh [--dry-run]
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"
REGION="us-east-1"
DRY="${1:-}"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }
ACCOUNT_ID=$(awsq sts get-caller-identity --query Account)

tag_ec2() { # id group cssenv
  echo "  EC2资源 $1 → Group=$2 CssEnv=$3"
  [ "$DRY" = "--dry-run" ] || aws --region "$REGION" ec2 create-tags --resources "$1" \
    --tags "Key=Group,Value=$2" "Key=CssEnv,Value=$3"
}

echo "=== 1) VPC / 子网 / 路由表 / IGW / 端点 / 安全组（共享 → css-shared）==="
for vpc_name in css-non-prod css-prod; do
  VPC=$(awsq ec2 describe-vpcs --filters "Name=tag:Name,Values=$vpc_name" --query 'Vpcs[0].VpcId')
  [ "$VPC" = "None" ] && continue
  IDS="$VPC"
  IDS="$IDS $(awsq ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId')"
  IDS="$IDS $(awsq ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" --query 'RouteTables[].RouteTableId')"
  IDS="$IDS $(awsq ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId')"
  IDS="$IDS $(awsq ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --query 'VpcEndpoints[].VpcEndpointId')"
  IDS="$IDS $(awsq ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query 'SecurityGroups[?GroupName!=`default`].GroupId')"
  for id in $IDS; do [ -n "$id" ] && [ "$id" != "None" ] && tag_ec2 "$id" "$vpc_name" "css-shared"; done
done

echo "=== 2) EC2 实例与 EIP ==="
# 应用机：CssEnv=css-<env>（部署目标，必须精确）；网关/堡垒：css-shared（绝不能被部署选中）
while read -r id name; do
  [ -z "$id" ] && continue
  case "$name" in
    css-test-app) tag_ec2 "$id" css-non-prod css-test ;;
    css-uat-app)  tag_ec2 "$id" css-non-prod css-uat ;;
    css-prod-app) tag_ec2 "$id" css-prod     css-prod ;;
    css-non-prod-gw)  tag_ec2 "$id" css-non-prod css-shared ;;
    css-prod-bastion) tag_ec2 "$id" css-prod     css-shared ;;
    *) echo "  [跳过未知实例] $name $id" ;;
  esac
done < <(awsq ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" \
          --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' | tr '\t' ' ')
# EIP 分两类：① 我们自己申请给网关/堡垒机的（有 Name 标签）；② ALB 的节点地址（无 Name，
# 关联的 ENI 描述形如 "ELB app/css-test/xxxx"）。注意别用 *prod-* 通配判断组——它会把
# css-non-prod-gw-eip 误判成生产（"non-prod-" 里就含 "prod-"），必须用 css-prod 前缀精确匹配。
while read -r alloc name eni; do
  [ -z "$alloc" ] || [ "$alloc" = "None" ] && continue
  ENVTAG="css-shared"
  case "$name" in
    css-prod-*) G=css-prod ;;
    css-nonprod-*|css-non-prod-*) G=css-non-prod ;;
    *)  # 无 Name → 看 ENI 描述里的 ELB 名，归到对应环境
      D=$(awsq ec2 describe-network-interfaces --network-interface-ids "$eni" --query 'NetworkInterfaces[0].Description' 2>/dev/null || echo "")
      case "$D" in
        *app/css-test/*) G=css-non-prod; ENVTAG=css-test ;;
        *app/css-uat/*)  G=css-non-prod; ENVTAG=css-uat ;;
        *app/css-prod/*) G=css-prod;     ENVTAG=css-prod ;;
        *) G=css-non-prod ;;
      esac ;;
  esac
  tag_ec2 "$alloc" "$G" "$ENVTAG"
done < <(awsq ec2 describe-addresses --query 'Addresses[].[AllocationId,Tags[?Key==`Name`]|[0].Value,NetworkInterfaceId]' | tr '\t' ' ')

echo "=== 3) EBS 卷（跟随所属实例）==="
while read -r vol env; do
  [ -z "$vol" ] && continue
  case "$env" in css-prod) G=css-prod ;; *) G=css-non-prod ;; esac
  tag_ec2 "$vol" "$G" "$env"
done < <(awsq ec2 describe-volumes --query 'Volumes[].[VolumeId,Attachments[0].InstanceId]' | while read -r v i; do
  [ -z "$i" ] || [ "$i" = "None" ] && continue
  e=$(awsq ec2 describe-instances --instance-ids "$i" --query 'Reservations[0].Instances[0].Tags[?Key==`CssEnv`]|[0].Value')
  echo "$v ${e:-css-shared}"; done)

echo "=== 4) RDS 实例与子网组 ==="
for db in css-non-prod css-prod; do
  ARN=$(awsq rds describe-db-instances --db-instance-identifier "$db" --query 'DBInstances[0].DBInstanceArn' 2>/dev/null || echo None)
  [ "$ARN" = "None" ] && continue
  case "$db" in css-prod) G=css-prod; E=css-prod ;; *) G=css-non-prod; E=css-shared ;; esac  # 非生产实例 test+uat 共用
  echo "  RDS $db → Group=$G CssEnv=$E"
  [ "$DRY" = "--dry-run" ] || aws --region "$REGION" rds add-tags-to-resource --resource-name "$ARN" \
    --tags "Key=Group,Value=$G" "Key=CssEnv,Value=$E"
done
for sg in css-non-prod-db-subnets css-prod-db-subnets; do
  ARN="arn:aws:rds:$REGION:$ACCOUNT_ID:subgrp:$sg"
  case "$sg" in css-prod*) G=css-prod ;; *) G=css-non-prod ;; esac
  [ "$DRY" = "--dry-run" ] || aws --region "$REGION" rds add-tags-to-resource --resource-name "$ARN" \
    --tags "Key=Group,Value=$G" "Key=CssEnv,Value=css-shared" 2>/dev/null && echo "  RDS 子网组 $sg → $G / css-shared" || true
done

echo "=== 5) ALB 与目标组 ==="
for env in test uat prod; do
  case "$env" in prod) G=css-prod ;; *) G=css-non-prod ;; esac
  ARN=$(awsq elbv2 describe-load-balancers --names "css-$env" --query 'LoadBalancers[0].LoadBalancerArn' 2>/dev/null || echo None)
  if [ "$ARN" != "None" ] && [ -n "$ARN" ]; then
    echo "  ALB css-$env → Group=$G CssEnv=css-$env"
    [ "$DRY" = "--dry-run" ] || aws --region "$REGION" elbv2 add-tags --resource-arns "$ARN" \
      --tags "Key=Group,Value=$G" "Key=CssEnv,Value=css-$env"
  fi
  TG=$(awsq elbv2 describe-target-groups --names "css-$env-fe-tg" --query 'TargetGroups[0].TargetGroupArn' 2>/dev/null || echo None)
  if [ "$TG" != "None" ] && [ -n "$TG" ]; then
    [ "$DRY" = "--dry-run" ] || aws --region "$REGION" elbv2 add-tags --resource-arns "$TG" \
      --tags "Key=Group,Value=$G" "Key=CssEnv,Value=css-$env"
    echo "  目标组 css-$env-fe-tg → Group=$G CssEnv=css-$env"
  fi
done

echo "=== 6) ECR 仓库 ==="
for env in test uat prod; do
  case "$env" in prod) G=css-prod ;; *) G=css-non-prod ;; esac
  for r in $(awsq ecr describe-repositories --query "repositories[?starts_with(repositoryName,'$env/')].repositoryArn"); do
    [ "$DRY" = "--dry-run" ] || aws --region "$REGION" ecr tag-resource --resource-arn "$r" \
      --tags "Key=Group,Value=$G" "Key=CssEnv,Value=css-$env"
  done
  echo "  ECR $env/* → Group=$G CssEnv=css-$env"
done

echo "=== 7) S3 桶 ==="
for env in test uat prod; do
  case "$env" in prod) G=css-prod ;; *) G=css-non-prod ;; esac
  for b in "css-$env" "css-$env-$ACCOUNT_ID"; do
    aws s3api list-buckets --query "Buckets[?Name=='$b'].Name" --output text | tr -d '\r' | grep -q . || continue
    [ "$DRY" = "--dry-run" ] || aws --region "$REGION" s3api put-bucket-tagging --bucket "$b" \
      --tagging "TagSet=[{Key=Name,Value=$b},{Key=Group,Value=$G},{Key=CssEnv,Value=css-$env}]"
    echo "  S3 $b → Group=$G CssEnv=css-$env"
  done
done
for b in "css-dbsync-$ACCOUNT_ID"; do
  aws s3api list-buckets --query "Buckets[?Name=='$b'].Name" --output text | tr -d '\r' | grep -q . || continue
  [ "$DRY" = "--dry-run" ] || aws --region "$REGION" s3api put-bucket-tagging --bucket "$b" \
    --tagging "TagSet=[{Key=Name,Value=$b},{Key=Group,Value=css-non-prod},{Key=CssEnv,Value=css-shared}]"
  echo "  S3 $b → css-non-prod / css-shared（运维中转桶）"
done

echo ""
echo "===== 标签补齐完成 ====="
echo "核对: Resource Groups & Tag Editor → 按标签 Group / CssEnv 搜索"
echo "      https://us-east-1.console.aws.amazon.com/resource-groups/tag-editor/find-resources?region=us-east-1"
