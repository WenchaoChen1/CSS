#!/usr/bin/env bash
# css-app-<env> 应用 S3 用户的 access key 管理（发放/查看）。
# 为什么用 IAM 用户而不是实例角色：后端代码要求显式的 S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY
# 两个环境变量（boto3 显式凭证），拿不到实例角色的临时凭证；本地开发机更是没有实例角色可用。
#
# ⚠️ 2026-07-31 起本脚本【不再创建用户/挂策略】——css-app-* 用户与其 S3 内联策略已全部由
#    css-terraform 接管（dev → css-non-prod/dev，test/uat → css-non-prod/<env>/iam，prod → css-prod/prod/iam），
#    再跑创建逻辑会绕过 state 造成 drift。本脚本只剩 access key 生命周期：红线规定 key 永不进
#    Terraform/state（secret 会明文落 state，见 css-terraform CLAUDE.md §九），所以发 key 永远走这里。
#    （2026-07-31 由 create-app-s3-user.sh 改名而来，名字对齐"只发 key"的现职能。）
#
# 用法: ./issue-app-s3-key.sh <dev|test|uat|support-ref|support-demo|support-sync|prod> [--new-key]
#   不带 --new-key：查看用户与现有 key 状态
#   带 --new-key  ：生成一对 access key 并【只打印这一次】（AWS 不会再给第二次）
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: issue-app-s3-key.sh <dev|test|uat|support-ref|support-demo|support-sync|prod> [--new-key]}"
NEWKEY="${2:-}"
REGION="us-east-1"
case "$ENV_NAME" in dev|test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "环境必须是 dev|test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;; esac
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
USER="css-app-$ENV_NAME"
BUCKET="css-$ENV_NAME-$ACCOUNT_ID"

if ! aws iam get-user --user-name "$USER" >/dev/null 2>&1; then
  case "$ENV_NAME" in
    dev)  STACK="css-non-prod/dev" ;;
    prod) STACK="css-prod/prod/iam" ;;
    *)    STACK="css-non-prod/$ENV_NAME/iam" ;;
  esac
  echo "[FATAL] 用户 $USER 不存在。用户/策略由 Terraform 管理——去 css-terraform/$STACK 下 apply，本脚本不建用户。"
  exit 1
fi

echo "用户: $USER（S3 内联策略由 css-terraform 管理，本脚本不动策略）"
echo "现有 access key："
aws iam list-access-keys --user-name "$USER" \
  --query 'AccessKeyMetadata[].[AccessKeyId,Status,CreateDate]' --output table

if [ "$NEWKEY" = "--new-key" ]; then
  N=$(aws iam list-access-keys --user-name "$USER" --query 'length(AccessKeyMetadata)' --output text | tr -d '\r')
  if [ "$N" -ge 2 ]; then
    echo "[FATAL] $USER 已有 2 个 access key（AWS 上限）。先删旧的:"
    echo "  aws iam delete-access-key --user-name $USER --access-key-id <ID>"
    exit 1
  fi
  OUT=$(aws iam create-access-key --user-name "$USER" --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text | tr -d '\r')
  read -r AKID SECRET <<< "$OUT"
  echo ""
  echo "===== 密钥已生成（SecretAccessKey 只显示这一次，务必立刻保存）====="
  echo "S3_ACCESS_KEY_ID=$AKID"
  echo "S3_SECRET_ACCESS_KEY=$SECRET"
  echo "S3_ENDPOINT_URL=https://s3.$REGION.amazonaws.com"
  echo "S3_STORAGE_BUCKET_NAME=$BUCKET"
  echo "S3_LOCATION=$REGION"
  echo ""
  echo "把上面 5 行覆盖进 deploy-env/$ENV_NAME/backend.env 的对应项；"
  [ "$ENV_NAME" = "dev" ] \
    && echo "dev 是本地开发环境，改完直接 .\\deploy\\windows\\本地dev.ps1 up 即可（不需要 put-params）" \
    || echo "然后 bash ../11-parameter-store/put-params.sh $ENV_NAME 并重新部署。"
else
  echo "（未生成密钥。需要时加 --new-key）"
fi
echo ""
echo "验证权限（用新密钥）: AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… aws s3 ls s3://$BUCKET/"
