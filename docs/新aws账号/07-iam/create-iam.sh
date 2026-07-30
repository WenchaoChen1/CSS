#!/usr/bin/env bash
# 创建 CI/CD 与运行所需的 IAM（零成本）：GitHub OIDC provider + 三环境完全隔离的
# 部署角色(css-deploy-<env>) / EC2 实例角色(css-ec2-<env>) / 应用 S3 用户(css-app-<env>，不生成 key)。
# 凭证隔离原则：任何 key/角色不跨环境复用，权限只够本环境（docs/生产部署/03 §4.5）。
# 幂等：存在即复用/覆盖 put-role-policy。用法: ./create-iam.sh
set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
ORG="Chain-Serve-Solutions"
REPOS=("Chain-Service-Solutions-Backend" "Chain-Service-Solutions-Frontend")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Windows git-bash：aws.exe 无法解析 MSYS 的 /tmp 路径，file:// 引用需转成 Windows 路径
if command -v cygpath >/dev/null 2>&1; then TMPF=$(cygpath -m "$TMP"); else TMPF="$TMP"; fi

# ---------- GitHub OIDC provider ----------
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com >/dev/null
  echo "OIDC provider 创建: $OIDC_ARN"
else
  echo "OIDC provider 复用: $OIDC_ARN"
fi

ensure_env() { # env branch gh_environment group
  local env=$1 branch=$2 ghenv=$3 group=$4
  local deploy_role="css-deploy-$env" ec2_role="css-ec2-$env" app_user="css-app-$env"

  # ---- CI/CD 角色（每环境一个，可推镜像+可部署；2026-07-28 用户拍板不拆 push/deploy）----
  # 信任：两仓库对应分支的 push（build job）+ 对应 environment（migrate/deploy job）。
  # environment 名与分支名一律相同（test/uat/main）——2026-07-29 用户拍板，弃用 production 这个例外名。
  # 本组织的 GitHub OIDC sub 是带唯一 ID 的新格式（CloudTrail 实测）：
  #   repo:Chain-Serve-Solutions@309824177/Chain-Service-Solutions-Frontend@1314034286:ref:refs/heads/test
  # 故新旧两种格式各写一份；@* 只通配 GitHub 附加的数字 ID，组织/仓库名仍是精确匹配（名字里不允许 @）。
  cat > "$TMP/trust-$env.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "$OIDC_ARN" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": [
        "repo:$ORG/${REPOS[0]}:ref:refs/heads/$branch",
        "repo:$ORG/${REPOS[1]}:ref:refs/heads/$branch",
        "repo:$ORG/${REPOS[0]}:environment:$ghenv",
        "repo:$ORG/${REPOS[1]}:environment:$ghenv",
        "repo:$ORG@*/${REPOS[0]}@*:ref:refs/heads/$branch",
        "repo:$ORG@*/${REPOS[1]}@*:ref:refs/heads/$branch",
        "repo:$ORG@*/${REPOS[0]}@*:environment:$ghenv",
        "repo:$ORG@*/${REPOS[1]}@*:environment:$ghenv"
      ] }
    }
  }]
}
EOF
  if ! aws iam get-role --role-name "$deploy_role" >/dev/null 2>&1; then
    aws iam create-role --role-name "$deploy_role" \
      --assume-role-policy-document "file://$TMPF/trust-$env.json" \
      --tags Key=Group,Value="$group" >/dev/null
    echo "角色创建: $deploy_role"
  else
    aws iam update-assume-role-policy --role-name "$deploy_role" \
      --policy-document "file://$TMPF/trust-$env.json"
    echo "角色复用(信任策略已刷新): $deploy_role"
  fi

  local rds_stmt=""
  if [ "$env" != "test" ]; then
    rds_stmt=',{ "Sid": "RdsSnapshot", "Effect": "Allow",
      "Action": ["rds:CreateDBSnapshot","rds:DescribeDBInstances","rds:DescribeDBSnapshots","rds:AddTagsToResource"],
      "Resource": "*" }'
  fi
  cat > "$TMP/deploy-policy-$env.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "EcrAuth", "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    { "Sid": "EcrPushOwnEnvOnly", "Effect": "Allow",
      "Action": ["ecr:BatchCheckLayerAvailability","ecr:InitiateLayerUpload","ecr:UploadLayerPart",
                 "ecr:CompleteLayerUpload","ecr:PutImage","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer",
                 "ecr:DescribeRepositories","ecr:DescribeImages"],
      "Resource": "arn:aws:ecr:$REGION:$ACCOUNT_ID:repository/$env/*" },
    { "Sid": "SsmSendToOwnEnv", "Effect": "Allow", "Action": "ssm:SendCommand",
      "Resource": "arn:aws:ec2:$REGION:$ACCOUNT_ID:instance/*",
      "Condition": { "StringEquals": { "ssm:resourceTag/CssEnv": "css-$env" } } },
    { "Sid": "SsmDocument", "Effect": "Allow", "Action": "ssm:SendCommand",
      "Resource": "arn:aws:ssm:$REGION::document/AWS-RunShellScript" },
    { "Sid": "SsmRead", "Effect": "Allow",
      "Action": ["ssm:GetCommandInvocation","ssm:ListCommandInvocations","ssm:DescribeInstanceInformation"],
      "Resource": "*" },
    { "Sid": "OwnEnvParams", "Effect": "Allow",
      "Action": ["ssm:GetParameter","ssm:GetParameters","ssm:PutParameter"],
      "Resource": "arn:aws:ssm:$REGION:$ACCOUNT_ID:parameter/css/$env/*" },
    { "Sid": "DescribeInstances", "Effect": "Allow", "Action": "ec2:DescribeInstances", "Resource": "*" }$rds_stmt
  ]
}
EOF
  aws iam put-role-policy --role-name "$deploy_role" \
    --policy-name "css-deploy-$env-policy" \
    --policy-document "file://$TMPF/deploy-policy-$env.json"

  # ---- EC2 实例角色 ----
  cat > "$TMP/ec2-trust.json" <<'EOF'
{ "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" },
                  "Action": "sts:AssumeRole" }] }
EOF
  if ! aws iam get-role --role-name "$ec2_role" >/dev/null 2>&1; then
    aws iam create-role --role-name "$ec2_role" \
      --assume-role-policy-document "file://$TMPF/ec2-trust.json" \
      --tags Key=Group,Value="$group" >/dev/null
    echo "角色创建: $ec2_role"
  else
    echo "角色复用: $ec2_role"
  fi
  aws iam attach-role-policy --role-name "$ec2_role" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam attach-role-policy --role-name "$ec2_role" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
  cat > "$TMP/ec2-params-$env.json" <<EOF
{ "Version": "2012-10-17",
  "Statement": [{ "Sid": "ReadOwnEnvParams", "Effect": "Allow",
    "Action": ["ssm:GetParameter","ssm:GetParameters"],
    "Resource": "arn:aws:ssm:$REGION:$ACCOUNT_ID:parameter/css/$env/*" }] }
EOF
  aws iam put-role-policy --role-name "$ec2_role" \
    --policy-name "css-ec2-$env-params" \
    --policy-document "file://$TMPF/ec2-params-$env.json"
  if ! aws iam get-instance-profile --instance-profile-name "$ec2_role" >/dev/null 2>&1; then
    aws iam create-instance-profile --instance-profile-name "$ec2_role" >/dev/null
    aws iam add-role-to-instance-profile --instance-profile-name "$ec2_role" --role-name "$ec2_role"
    echo "实例 profile 创建: $ec2_role"
  fi

  # ---- 应用 S3 用户（key 与桶策略在 Parameter Store 填值阶段生成，避免闲置密钥）----
  if ! aws iam get-user --user-name "$app_user" >/dev/null 2>&1; then
    aws iam create-user --user-name "$app_user" --tags Key=Group,Value="$group" >/dev/null
    echo "S3 应用用户创建: $app_user（未生成 key）"
  else
    echo "S3 应用用户复用: $app_user"
  fi
}

# 清理 2026-07-28 短暂拆分过的 css-push-* 角色（已并回 css-deploy-*，幂等）
for e in test uat prod; do
  if aws iam get-role --role-name "css-push-$e" >/dev/null 2>&1; then
    aws iam delete-role-policy --role-name "css-push-$e" --policy-name "css-push-$e-policy" 2>/dev/null || true
    aws iam delete-role --role-name "css-push-$e"
    echo "已删除退役角色: css-push-$e"
  fi
done

ensure_env test test test       css-non-prod
ensure_env uat  uat  uat        css-non-prod
ensure_env prod main main       css-prod

echo ""
echo "===== IAM 就绪 ====="
echo "OIDC:      $OIDC_ARN"
echo "CI/CD 角色: css-deploy-{test,uat,prod}（每环境一个：本环境 ECR push + SSM + 参数 + 快照）"
echo "实例角色:  css-ec2-{test,uat,prod}（挂对应环境 EC2）"
echo "S3 用户:   css-app-{test,uat,prod}（key 待填值阶段生成）"
