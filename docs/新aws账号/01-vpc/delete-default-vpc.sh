#!/usr/bin/env bash
# 删除 AWS 账号自带的【默认 VPC】（及其子网/IGW/路由表/默认安全组）。
#
# 为什么删：我们所有资源都在自建的 css-non-prod / css-prod 两个 VPC 里，默认 VPC 完全空置。
#   留着它有两个坏处：① 它和它的 6 个子网**打不了有意义的标签**（不属于任何环境），
#   永远是标签合规检查里的例外；② 控制台/CLI 不显式指定 VPC 时会默认落到它里面，容易误建资源。
#
# 安全性：可逆——需要时 `aws ec2 create-default-vpc --region us-east-1` 一条命令即可重建
#   （新 VPC 会是新的 ID，但里面本来就没有东西）。脚本会在删之前逐项确认它确实是空的。
#
# 用法: ./delete-default-vpc.sh [region] yes
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

REGION="${1:-us-east-1}"
CONFIRM="${2:-}"
awsq() { aws --region "$REGION" --output text "$@" | tr -d '\r'; }

VPC=$(awsq ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId')
[ "$VPC" != "None" ] && [ -n "$VPC" ] || { echo "$REGION 没有默认 VPC（可能已删）"; exit 0; }
echo "默认 VPC: $VPC （区域 $REGION）"

# ---- 空置校验：任何一项非空都拒绝执行 ----
BAD=0
check() { # 描述 数量
  if [ "${2:-0}" != "0" ]; then echo "  [占用] $1: $2"; BAD=1; else echo "  [空] $1"; fi
}
check "EC2 实例"    "$(awsq ec2 describe-instances --filters "Name=vpc-id,Values=$VPC" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'length(Reservations)')"
check "网络接口"    "$(awsq ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --query 'length(NetworkInterfaces)')"
check "NAT 网关"    "$(awsq ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" "Name=state,Values=pending,available" --query 'length(NatGateways)')"
check "VPC 端点"    "$(awsq ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --query 'length(VpcEndpoints)')"
# RDS 的 default 子网组是 AWS 随默认 VPC 自动建的附属物，只要没实例用就能删（我们的
# create-rds.sh 一律显式指定 css-<组>-db-subnets，从不依赖 default）。非 default 的才算真占用。
RDS_SG_OTHER=$(awsq rds describe-db-subnet-groups --query "length(DBSubnetGroups[?VpcId=='$VPC' && DBSubnetGroupName!='default'])")
check "RDS 子网组(非 default)" "$RDS_SG_OTHER"
check "非默认安全组" "$(awsq ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC" --query "length(SecurityGroups[?GroupName!='default'])")"
check "对等连接"    "$(awsq ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$VPC" --query 'length(VpcPeeringConnections)')"
[ "$BAD" = "0" ] || { echo "默认 VPC 非空，拒绝删除"; exit 1; }

[ "$CONFIRM" = "yes" ] || { echo ""; echo "校验通过（完全空置）。加第二个参数 yes 才会真正删除："; echo "  ./delete-default-vpc.sh $REGION yes"; exit 0; }

echo "===== 开始删除 ====="
# RDS default 子网组（占着默认 VPC 的子网，不删则子网删不掉）
if awsq rds describe-db-subnet-groups --db-subnet-group-name default >/dev/null 2>&1; then
  INUSE=$(awsq rds describe-db-instances --query "length(DBInstances[?DBSubnetGroup.DBSubnetGroupName=='default'])")
  if [ "${INUSE:-0}" = "0" ]; then
    aws --region "$REGION" rds delete-db-subnet-group --db-subnet-group-name default       && echo "  已删 RDS default 子网组"
  else
    echo "  [FATAL] RDS default 子网组被 $INUSE 个实例使用，中止"; exit 1
  fi
fi
# 顺序：子网 → IGW（先 detach）→ 非主路由表 → VPC（默认安全组随 VPC 自动删）
for s in $(awsq ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" --query 'Subnets[].SubnetId'); do
  aws --region "$REGION" ec2 delete-subnet --subnet-id "$s" && echo "  已删子网 $s"
done
for g in $(awsq ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC" --query 'InternetGateways[].InternetGatewayId'); do
  aws --region "$REGION" ec2 detach-internet-gateway --internet-gateway-id "$g" --vpc-id "$VPC"
  aws --region "$REGION" ec2 delete-internet-gateway --internet-gateway-id "$g" && echo "  已删 IGW $g"
done
for r in $(awsq ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC" \
            --query 'RouteTables[?!(Associations[?Main==`true`])].RouteTableId'); do
  aws --region "$REGION" ec2 delete-route-table --route-table-id "$r" >/dev/null 2>&1 && echo "  已删路由表 $r" || true
done
aws --region "$REGION" ec2 delete-vpc --vpc-id "$VPC"
echo "===== 默认 VPC $VPC 已删除 ====="
echo "需要恢复时: aws ec2 create-default-vpc --region $REGION"
echo "现在账号内所有 VPC 都是自建且带完整标签的："
awsq ec2 describe-vpcs --query 'Vpcs[].[VpcId,Tags[?Key==`Name`]|[0].Value,Tags[?Key==`Group`]|[0].Value,Tags[?Key==`CssEnv`]|[0].Value]'
