#!/usr/bin/env bash
# 手动部署一个环境（CI 之外的兜底/回滚入口；日常部署已由 CI 自动执行——2026-07-28 曾为唯一部署入口）。
# 动作：本地打包 Backend 仓库 deploy/{compose,config,bin} → 经 SSM 上传到目标机 /opt/css-cicd/
#       → 执行 deploy.sh <env> deploy <stack> [tag]（渲染 env → pull → up → 冒烟 → 清理）。
# 用法: ./deploy-env.sh <test|uat|support-ref|support-demo|support-sync|prod> [stack] [image_tag]
# 通知：本入口会带 CSS_NOTIFY=1 —— 部署完成后 deploy.sh 发一条 Lark 卡片（"手动部署"字样），
#       与 CI 的通知不会重复（CI 调 deploy.sh 时不设该变量，由 workflow 的 notify job 负责发）。
#   stack: all(默认) | core(=infra+backend) | infra | backend | frontend
#   image_tag: 不可变版本 tag 如 test-v12（缺省用浮动 <env> tag，即最近一次 CI 推送）
# 迁移数据库: ./deploy-env.sh <env> migrate   （特殊 stack 值，执行 alembic upgrade head）
set -euo pipefail

ENV_NAME="${1:?用法: deploy-env.sh <test|uat|support-ref|support-demo|support-sync|prod> [stack|migrate] [image_tag]}"
STACK="${2:-all}"
TAG="${3:-}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/../../../CSS_backend-main/deploy"
[ -d "$DEPLOY_DIR/compose" ] || { echo "缺 $DEPLOY_DIR/compose"; exit 1; }

if [ "$ENV_NAME" = "prod" ]; then
  read -r -p "⚠️ 即将部署【生产环境】，输入 prod 确认: " ok
  [ "$ok" = "prod" ] || { echo "已取消"; exit 1; }
fi

B64=$(tar czf - -C "$DEPLOY_DIR" compose config bin | base64 -w0)
if [ "$STACK" = "migrate" ]; then
  ACTION="migrate all"
else
  ACTION="deploy $STACK"
fi

echo "上传 bundle（$(( ${#B64} / 1024 ))KB）并执行: deploy.sh $ENV_NAME $ACTION $TAG"
bash "$SCRIPT_DIR/run.sh" "$ENV_NAME" \
  "mkdir -p /opt/css-cicd && echo $B64 | base64 -d | tar xzf - -C /opt/css-cicd && chmod +x /opt/css-cicd/bin/deploy.sh && CSS_NOTIFY=1 /opt/css-cicd/bin/deploy.sh $ENV_NAME $ACTION $TAG"
