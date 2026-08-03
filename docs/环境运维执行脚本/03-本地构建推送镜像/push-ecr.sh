#!/usr/bin/env bash
# 本机手动构建并推送 7 个镜像到 ECR（CI 是主链路，本脚本是备用/首次灌仓工具）。
# 实现：渲染环境配置（优先 SSM Parameter Store，回退工作区 deploy-env/<env>/ 已有文件）→ ECR 登录 →
#       委托后端仓库 deploy/aws/build-push.sh（与 CI 同一套构建定义，双 tag：不可变版本 + <env> 浮动；
#       CI 版本号为 <env>-vN，本脚本手动推送缺省 <env>-manual-<sha7> 以免与 CI 版本序列混淆）。
# 用法: ./push-ecr.sh <test|uat|prod> [tag]
# 前置: Docker Desktop 运行中；aws cli 凭证有 ECR push 与本环境参数读取权限；
#       前端构建需要同级存在 ../CSS_frontend-main（工作区默认布局）。
set -euo pipefail

ENV_NAME="${1:?用法: push-ecr.sh <test|uat|prod> [tag]}"
case "$ENV_NAME" in test|uat|prod) ;; *) echo "环境必须是 test|uat|prod"; exit 1 ;; esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"           # 工作区根 chain-serve/
BACKEND="$ROOT/CSS_backend-main"
REGION="us-east-1"
ENV_DIR="$ROOT/deploy-env/$ENV_NAME"   # 环境配置在工作区根（2026-07-28 迁出后端仓库）
mkdir -p "$ENV_DIR"

render() {  # $1=参数名 $2=目标文件；Parameter Store 不可用时回退目标位置已有文件
  if aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption \
       --query 'Parameter.Value' --output text > "$2.tmp" 2>/dev/null; then
    # 覆盖前先备份并提示差异：这里是"远程 → 本地底稿"的反向覆盖，本地未推送的编辑会被冲掉
    # （与 11-parameter-store/put-params.sh 的防误覆盖对称；2026-08-03 加）
    if [ -f "$2" ] && ! cmp -s <(tr -d '\r' < "$2") <(tr -d '\r' < "$2.tmp"); then
      cp "$2" "$2.local-bak"
      echo "⚠️ 本地底稿与 Parameter Store 不一致，已备份原文件到 $2.local-bak；差异键（只列 KEY）："
      diff <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$2" | sort -u) \
           <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$2.tmp" | sort -u) | grep -E '^[<>]' | tr -d '=' | sed 's/^/      /' || true
    fi
    mv "$2.tmp" "$2"; echo "已从 Parameter Store 渲染: $1"
  else
    rm -f "$2.tmp"
    if [ -f "$2" ]; then echo "⚠️ Parameter Store 不可用，沿用已有 $2"
    else echo "缺参数 $1 且本地无 $2"; exit 1; fi
  fi
}
render "/css/$ENV_NAME/backend.env"  "$ENV_DIR/backend.env"
render "/css/$ENV_NAME/frontend.env" "$ENV_DIR/frontend.env"

getvar() { { grep -E "^$1=" "$ENV_DIR/backend.env" || true; } | tail -1 | cut -d= -f2- | tr -d '"\r'; }
export ECR_REGISTRY="$(getvar ECR_REGISTRY)"
[ -n "$ECR_REGISTRY" ] || { echo "backend.env 缺 ECR_REGISTRY"; exit 1; }

SHA=$(git -C "$BACKEND" rev-parse --short=7 HEAD 2>/dev/null | tr -d '\r' || echo unknown)
TAG="${2:-$ENV_NAME-manual-$SHA}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
bash "$BACKEND/deploy/aws/build-push.sh" "$ENV_NAME" "$TAG" all

echo "===== 手动推送完成: 7 镜像 × {$TAG, $ENV_NAME} ====="
