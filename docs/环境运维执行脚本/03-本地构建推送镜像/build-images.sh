#!/usr/bin/env bash
# 本地【只构建、不推送】镜像（Windows 开发机用；打出的镜像 tag 与推送版完全同规格，
# 之后想推可直接 push-ecr.sh 或手动 docker push）。
# 与 CI/push-ecr.sh 同一套构建定义（Backend 仓库 deploy/compose/*.yml），不会出现"本地打的和线上不一样"。
#
# 用法: ./build-images.sh <test|uat|support-ref|support-demo|support-sync|prod> [tag] [backend|frontend|all]
#   tag  缺省 <env>-local-<后端 git sha7>
#   例:  ./build-images.sh test                    # 构建 6 个后端镜像
#        ./build-images.sh test '' all             # 后端 + 前端（需同级存在 ../CSS_frontend-main）
#        ./build-images.sh uat uat-local1 frontend
# 前置: Docker Desktop 运行中；工作区根 deploy-env/<env>/backend.env 存在（提供 ECR_REGISTRY 等构建变量；
#       不存在时用最小内置值，仅影响镜像名前缀）。本地 dev 环境打镜像不走本脚本——用
#       CSS_backend-main\deploy\windows\本地dev.ps1 build。
set -euo pipefail

ENV_NAME="${1:?用法: build-images.sh <test|uat|support-ref|support-demo|support-sync|prod> [tag] [backend|frontend|all]}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|support-sync|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|support-sync|prod"; exit 1 ;; esac
SCOPE="${3:-backend}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BACKEND="$ROOT/CSS_backend-main"
cd "$BACKEND"

TAG="${2:-}"
[ -n "$TAG" ] || TAG="${ENV_NAME}-local-$(git rev-parse --short=7 HEAD 2>/dev/null || echo dev)"

export DOCKER_DEFAULT_PLATFORM="${DOCKER_DEFAULT_PLATFORM:-linux/amd64}"   # 与 EC2 一致

# 环境配置：优先工作区底稿；缺失时生成最小构建 env（只为镜像名变量，密钥无关）
ENV_FILE="$ROOT/deploy-env/$ENV_NAME/backend.env"
if [ ! -f "$ENV_FILE" ]; then
  ENV_FILE="$(mktemp -d)/backend.build.env"
  printf 'DEPLOY_ENV=%s\nENV=%s\nECR_REGISTRY=582797602427.dkr.ecr.us-east-1.amazonaws.com\nECR_REPO_PREFIX=%s/css-backend\nECR_FRONTEND_PREFIX=%s/css-frontend\nENV_FILE=%s\n' \
    "$ENV_NAME" "$ENV_NAME" "$ENV_NAME" "$ENV_NAME" "$ENV_FILE" > "$ENV_FILE"
  echo "（未找到 deploy-env/$ENV_NAME/backend.env，使用最小内置构建变量）"
fi
export ENV_FILE IMAGE_TAG="$TAG"

compose() { docker compose --project-directory deploy --env-file "$ENV_FILE" "$@"; }

if [ "$SCOPE" = "backend" ] || [ "$SCOPE" = "all" ]; then
  compose -f deploy/compose/backend.yml build app nginx sms_sender email_sender ai_assistant ocr-migrator
fi
if [ "$SCOPE" = "frontend" ] || [ "$SCOPE" = "all" ]; then
  [ -d "$ROOT/CSS_frontend-main" ] || { echo "缺同级 ../CSS_frontend-main，无法构建前端"; exit 1; }
  compose -f deploy/compose/frontend.yml build frontend
fi

echo "===== 本地构建完成（未推送）: env=$ENV_NAME scope=$SCOPE tag=$TAG ====="
echo "查看: docker images | grep '$ENV_NAME/'"
echo "要推送: bash $SCRIPT_DIR/push-ecr.sh $ENV_NAME $TAG"
