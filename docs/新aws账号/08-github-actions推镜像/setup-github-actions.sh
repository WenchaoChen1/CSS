#!/usr/bin/env bash
# 一键配置 GitHub Actions 自动推镜像/部署所需的仓库设置（Variables + Environments + prod 审批人）。
# workflow 文件本身已在两仓库 .github/workflows/cicd.yml（push test/uat/main 自动触发）——本脚本只做"仓库侧配置"。
# 用法: ./setup-github-actions.sh <backend|frontend|all>
# 前置: 安装 GitHub CLI 并登录 charles221900 账号:
#   winget install GitHub.cli   （或 https://cli.github.com）
#   gh auth login               （选 GitHub.com → HTTPS → 浏览器登录 charles221900）
set -euo pipefail

TARGET="${1:?用法: setup-github-actions.sh <backend|frontend|all>}"
ORG="Chain-Serve-Solutions"
ACCOUNT_ID="582797602427"
REVIEWER="charles221900"   # production 环境的审批人

case "$TARGET" in
  backend)  REPOS=("Chain-Service-Solutions-Backend") ;;
  frontend) REPOS=("Chain-Service-Solutions-Frontend") ;;
  all)      REPOS=("Chain-Service-Solutions-Backend" "Chain-Service-Solutions-Frontend") ;;
  *) echo "参数必须是 backend|frontend|all"; exit 1 ;;
esac

command -v gh >/dev/null || { echo "缺 GitHub CLI: winget install GitHub.cli 后 gh auth login"; exit 1; }
gh auth status >/dev/null || { echo "先 gh auth login（charles221900 账号）"; exit 1; }

REVIEWER_ID=$(gh api "users/$REVIEWER" --jq .id)

for repo in "${REPOS[@]}"; do
  FULL="$ORG/$repo"
  echo "===== 配置 $FULL ====="

  # ---- 1) Repository variables（值与 docs/环境/配置速查.md §2 一致）----
  gh variable set AWS_ROLE_ARN_TEST --repo "$FULL" --body "arn:aws:iam::${ACCOUNT_ID}:role/css-deploy-test"
  gh variable set AWS_ROLE_ARN_UAT  --repo "$FULL" --body "arn:aws:iam::${ACCOUNT_ID}:role/css-deploy-uat"
  gh variable set AWS_ROLE_ARN_PROD --repo "$FULL" --body "arn:aws:iam::${ACCOUNT_ID}:role/css-deploy-prod"
  gh variable set ECR_REGISTRY      --repo "$FULL" --body "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
  echo "  Variables ×4 已写入"

  # ---- 2) Environments：test / uat 无保护；production 加 Required reviewers ----
  gh api -X PUT "repos/$FULL/environments/test" >/dev/null
  gh api -X PUT "repos/$FULL/environments/uat"  >/dev/null
  gh api -X PUT "repos/$FULL/environments/production" \
    --input - >/dev/null <<EOF
{ "reviewers": [ { "type": "User", "id": $REVIEWER_ID } ] }
EOF
  echo "  Environments ×3 已创建（production 审批人: $REVIEWER）"

  # ---- 3) 校验 ----
  echo "  当前 variables:"
  gh variable list --repo "$FULL" | sed 's/^/    /'
done

echo ""
echo "===== 完成。验证方式 ====="
echo "1. 推空提交触发: git commit --allow-empty -m 'ci: trigger' && git push neworg test"
echo "2. 或手动触发:   gh workflow run cicd.yml --repo $ORG/${REPOS[0]} --ref test -f environment=test"
echo "3. 观看运行:     https://github.com/$ORG/<仓库>/actions"
