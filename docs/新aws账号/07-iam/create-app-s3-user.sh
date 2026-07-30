#!/usr/bin/env bash
# 应用访问 S3 的 IAM 用户：css-app-<env>，权限【只限本环境的桶】。
# 为什么用 IAM 用户而不是实例角色：后端代码要求显式的 S3_ACCESS_KEY_ID / S3_SECRET_ACCESS_KEY
# 两个环境变量（boto3 显式凭证），拿不到实例角色的临时凭证；本地开发机更是没有实例角色可用。
#
# 权限范围（最小集）：
#   桶级  ListBucket / GetBucketLocation      —— 只对自己那个桶
#   对象级 PutObject / GetObject / DeleteObject / 分段上传相关 —— 只对该桶内的对象
#   显式拒绝跨桶：策略 Resource 精确到本桶 ARN，其它桶一律无权。
#
# 用法: ./create-app-s3-user.sh <dev|test|uat|prod> [--new-key]
#   不带 --new-key：只建用户+挂策略（不生成密钥，避免闲置凭证）
#   带 --new-key  ：额外生成一对 access key 并【只打印这一次】（AWS 不会再给第二次）
#   例: ./create-app-s3-user.sh dev --new-key     # 本地开发要用，需要密钥
#       ./create-app-s3-user.sh test             # 部署环境，先挂策略，用时再发 key
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

ENV_NAME="${1:?用法: create-app-s3-user.sh <dev|test|uat|prod> [--new-key]}"
NEWKEY="${2:-}"
REGION="us-east-1"
case "$ENV_NAME" in
  dev|test|uat) GROUP=css-non-prod ;;
  prod)         GROUP=css-prod ;;
  *) echo "环境必须是 dev|test|uat|prod"; exit 1 ;;
esac
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
USER="css-app-$ENV_NAME"
BUCKET="css-$ENV_NAME-$ACCOUNT_ID"

# 桶必须先存在，否则策略指向一个不存在的资源
if ! aws s3api list-buckets --query "Buckets[?Name=='$BUCKET'].Name" --output text | tr -d '\r' | grep -q .; then
  echo "桶 $BUCKET 不存在——先跑 ../13-s3/create-s3.sh $ENV_NAME"; exit 1
fi

if aws iam get-user --user-name "$USER" >/dev/null 2>&1; then
  echo "用户已存在: $USER"
else
  aws iam create-user --user-name "$USER" \
    --tags Key=Group,Value="$GROUP" Key=CssEnv,Value="css-$ENV_NAME" >/dev/null
  echo "用户创建: $USER"
fi
# 标签补齐（老用户可能建的时候没打全）
aws iam tag-user --user-name "$USER" --tags Key=Group,Value="$GROUP" Key=CssEnv,Value="css-$ENV_NAME" >/dev/null

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMPF=$(cygpath -m "$TMP"); else TMPF="$TMP"; fi
cat > "$TMP/s3.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "BucketLevel", "Effect": "Allow",
      "Action": ["s3:ListBucket","s3:GetBucketLocation","s3:ListBucketMultipartUploads"],
      "Resource": "arn:aws:s3:::$BUCKET" },
    { "Sid": "ObjectLevel", "Effect": "Allow",
      "Action": ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],
      "Resource": "arn:aws:s3:::$BUCKET/*" }
  ]
}
EOF
aws iam put-user-policy --user-name "$USER" --policy-name "$USER-s3" \
  --policy-document "file://$TMPF/s3.json"
echo "策略已挂: $USER-s3 → 仅 s3://$BUCKET （上传/下载/删除/分段上传）"

if [ "$NEWKEY" = "--new-key" ]; then
  N=$(aws iam list-access-keys --user-name "$USER" --query 'length(AccessKeyMetadata)' --output text | tr -d '\r')
  if [ "$N" -ge 2 ]; then
    echo "[FATAL] $USER 已有 2 个 access key（AWS 上限）。先删旧的:"
    aws iam list-access-keys --user-name "$USER" --query 'AccessKeyMetadata[].[AccessKeyId,Status,CreateDate]' --output text
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
