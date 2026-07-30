#!/usr/bin/env bash
# 创建各环境的应用存储桶（发票/目录/上传文件等）：css-test / css-uat / css-prod。
# 桶：阻断一切公共访问 + SSE-S3 默认加密 + 版本控制 + 生命周期（非当前版本 30 天清理）+ 双标签。
# 命名（2026-07-29 用户拍板，三环境统一）：**css-<env>-<账号ID>**，如 css-test-582797602427。
# 为什么一律带账号后缀：S3 桶名是【全球唯一】命名空间（跨账号跨区域共用），纯名 css-test / css-prod
# 早被别的 AWS 账号占了，只有 css-uat 当时侥幸可用。与其三个环境两种写法，不如统一带后缀——
# 既保证一定建得出来，也一眼看出属于哪个账号。
# 用法: ./create-s3.sh [dev|test|uat|prod|all]   （缺省 all=三个部署环境；dev 需显式指定）
#   dev 桶供【本地开发】直传真实 S3 用（本地 dev 原本连的是 localhost:9000 的 MinIO）
set -euo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

SCOPE="${1:-all}"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
case "$SCOPE" in
  all) ENVS=(test uat prod) ;;   # dev 不在 all 里：它是本地开发桶，按需单独建
  dev|test|uat|prod) ENVS=("$SCOPE") ;;
  *) echo "参数必须是 dev|test|uat|prod|all"; exit 1 ;;
esac

LIFECYCLE='{
  "Rules": [
    { "ID": "abort-incomplete-uploads", "Status": "Enabled", "Filter": {},
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 } },
    { "ID": "expire-noncurrent-versions", "Status": "Enabled", "Filter": {},
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 } }
  ]
}'

RESULT=""
for env in "${ENVS[@]}"; do
  case "$env" in prod) GROUP=css-prod ;; *) GROUP=css-non-prod ;; esac
  # dev 归入非生产组，CssEnv 用 css-dev（本地开发，不是部署环境）
  BUCKET="css-$env-$ACCOUNT_ID"     # 三环境统一带账号后缀（见文件头说明）

  # 归属判断只认 list-buckets：head-bucket 对【别人的公开桶】也会返回成功（纯名 css-test 就被别的账号
  # 占着、桶在 ap-northeast-1），拿它判断会误判成"我们已有"，后续所有 put-* 全部 AccessDenied。
  owned() { aws s3api list-buckets --query "Buckets[?Name=='"'"'$1'"'"'].Name" --output text | tr -d '
' | grep -q .; }
  if owned "$BUCKET"; then
    echo "桶已存在（本账号）: $BUCKET"
  else
    aws --region "$REGION" s3api create-bucket --bucket "$BUCKET" >/dev/null
    echo "桶创建: $BUCKET"
  fi

  aws --region "$REGION" s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws --region "$REGION" s3api put-bucket-encryption --bucket "$BUCKET" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
  aws --region "$REGION" s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
  aws --region "$REGION" s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --lifecycle-configuration "$LIFECYCLE"
  aws --region "$REGION" s3api put-bucket-tagging --bucket "$BUCKET" \
    --tagging "TagSet=[{Key=Name,Value=$BUCKET},{Key=Group,Value=$GROUP},{Key=CssEnv,Value=css-$env}]"
  # 应用要用预签名 URL 直传/直读时才需要 CORS；先给一个最小可用配置（生产请把 AllowedOrigins 收成真实域名）
  aws --region "$REGION" s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration '{
    "CORSRules": [{ "AllowedHeaders": ["*"], "AllowedMethods": ["GET","PUT","POST","HEAD"],
                    "AllowedOrigins": ["*"], "ExposeHeaders": ["ETag"], "MaxAgeSeconds": 3000 }]
  }'
  echo "  已配置: 阻断公共访问 / SSE-S3 / 版本控制 / 生命周期 / 标签 Group=$GROUP CssEnv=css-$env"
  RESULT="$RESULT
  $env → $BUCKET"
done

echo ""
echo "===== S3 完成 ====="
echo "桶名映射:$RESULT"
echo ""
echo "下一步（每个环境）："
echo "  1) 把桶名写进 deploy-env/<env>/backend.env 的 S3_STORAGE_BUCKET_NAME，再 11-parameter-store/put-params.sh <env>"
echo "  2) 给该环境的应用用户 css-app-<env> 生成 key 并授权【仅该桶】（见 07-iam/README 的 S3 用户一节）"
