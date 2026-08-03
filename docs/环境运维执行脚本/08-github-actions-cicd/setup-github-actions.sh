#!/usr/bin/env bash
# 一键配置 GitHub Actions 自动推镜像/部署所需的仓库设置（Variables + Environments）。
# workflow 文件本身已在两仓库 .github/workflows/cicd.yml（push test/uat/main 自动触发）——本脚本只做"仓库侧配置"。
# 📌 2026-07-29 起：GitHub environment 名与分支名一律相同 —— test / uat / main（生产 environment 就叫 main，
#    弃用原先的例外名 production）。三个环境已手工建齐，本脚本幂等重跑无副作用。
# 用法: ./setup-github-actions.sh <backend|frontend|all>
# 前置: 安装 GitHub CLI 并登录 charles221900 账号:
#   winget install GitHub.cli   （或 https://cli.github.com）
#   gh auth login               （选 GitHub.com → HTTPS → 浏览器登录 charles221900）
set -euo pipefail

TARGET="${1:?用法: setup-github-actions.sh <backend|frontend|all>}"
ORG="Chain-Serve-Solutions"
ACCOUNT_ID="582797602427"
REVIEWER="charles221900"   # main 环境（=生产）的审批人；GitHub Free 私有仓库不支持环境审批，此项仅 Team+ 计划生效

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

  # ---- 1) Repository variables（值与 deploy-env/运维访问速查.local.md §2 一致）----
  gh variable set AWS_ROLE_ARN_TEST --repo "$FULL" --body "arn:aws:iam::${ACCOUNT_ID}:role/css-deploy-test"
  gh variable set AWS_ROLE_ARN_UAT  --repo "$FULL" --body "arn:aws:iam::${ACCOUNT_ID}:role/css-deploy-uat"
  gh variable set AWS_ROLE_ARN_PROD --repo "$FULL" --body "arn:aws:iam::${ACCOUNT_ID}:role/css-deploy-prod"
  gh variable set ECR_REGISTRY      --repo "$FULL" --body "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
  echo "  Variables ×4 已写入"

  # ---- 2) Environments：名字=分支名（test / uat / main）；main 试着加 Required reviewers（Free 计划会被拒，无妨）----
  gh api -X PUT "repos/$FULL/environments/test" >/dev/null
  gh api -X PUT "repos/$FULL/environments/uat"  >/dev/null
  # main 环境：Free 私有仓库不支持 Required reviewers，带 reviewers 的请求会被拒 →
  # 先试带审批人，失败则退回创建纯环境（人工闸由"手动 Run workflow"承担）。2026-08-03 加容错。
  if gh api -X PUT "repos/$FULL/environments/main" --input - >/dev/null 2>&1 <<EOF
{ "reviewers": [ { "type": "User", "id": $REVIEWER_ID } ] }
EOF
  then
    echo "  Environments ×3 已创建（test / uat / main；main 审批人: $REVIEWER）"
  else
    gh api -X PUT "repos/$FULL/environments/main" >/dev/null
    echo "  Environments ×3 已创建（test / uat / main；⚠️ Free 计划不支持 Required reviewers，main 无审批人——生产闸=手动 Run workflow）"
  fi

  # ---- 3) 校验 ----
  echo "  当前 variables:"
  gh variable list --repo "$FULL" | sed 's/^/    /'
done

echo ""
echo "===== 完成。验证方式 ====="
echo "1. 推空提交触发: git commit --allow-empty -m 'ci: trigger' && git push neworg test"
echo "2. 或手动触发:   gh workflow run cicd.yml --repo $ORG/${REPOS[0]} --ref test -f environment=test"
echo "3. 观看运行:     https://github.com/$ORG/<仓库>/actions"
