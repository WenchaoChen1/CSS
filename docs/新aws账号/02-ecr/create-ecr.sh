#!/usr/bin/env bash
# 创建 ECR 镜像仓库（幂等）：**每环境独立仓库**（2026-07-28 拍板：test/uat/prod 镜像不共用仓库）。
# 命名规范: <env>/css-backend/{app,nginx,sms-sender,email-sender,ai-assistant,catalog-ocr} + <env>/css-frontend/app
# 共 3 环境 × 7 = 21 个仓库；每个开推送扫描 + lifecycle 只保留最近 5 个镜像。
# 用法: ./create-ecr.sh [test|uat|prod|all]   （缺省 all）
set -euo pipefail
REGION="us-east-1"
SCOPE="${1:-all}"

case "$SCOPE" in
  all) ENVS=(test uat prod) ;;
  test|uat|prod) ENVS=("$SCOPE") ;;
  *) echo "参数必须是 test|uat|prod|all"; exit 1 ;;
esac

REPOS=(
  css-backend/app
  css-backend/nginx
  css-backend/sms-sender
  css-backend/email-sender
  css-backend/ai-assistant
  css-backend/catalog-ocr
  css-frontend/app
)

# 只保留最近 5 个镜像（按 push 时间，任何 tag 状态）——环境浮动 tag 总是骑在最新镜像上不受影响
LIFECYCLE='{
  "rules": [{
    "rulePriority": 1,
    "description": "keep last 5 images",
    "selection": { "tagStatus": "any", "countType": "imageCountMoreThan", "countNumber": 5 },
    "action": { "type": "expire" }
  }]
}'

for env in "${ENVS[@]}"; do
  case "$env" in prod) GROUP=css-prod ;; *) GROUP=css-non-prod ;; esac
  for base in "${REPOS[@]}"; do
    repo="$env/$base"
    if aws ecr describe-repositories --region "$REGION" --repository-names "$repo" >/dev/null 2>&1; then
      echo "仓库复用: $repo"
    else
      aws ecr create-repository --region "$REGION" --repository-name "$repo" \
        --image-scanning-configuration scanOnPush=true \
        --tags Key=Group,Value="$GROUP" Key=CssEnv,Value="css-$env" >/dev/null
      echo "仓库创建: $repo"
    fi
    aws ecr put-lifecycle-policy --region "$REGION" --repository-name "$repo" \
      --lifecycle-policy-text "$LIFECYCLE" >/dev/null
  done
  echo "---- $env 环境 7 仓库就绪（scanOnPush + 保留 5） ----"
done
echo "===== ECR 完成: ${ENVS[*]} ====="
echo "注: 2026-07-28 全量清理过一次（含旧无前缀仓库与 css-backend/db）；db/pgadmin 不建仓库——数据库走 RDS,pgadmin 仅本地 dev 用 Docker Hub 镜像"
