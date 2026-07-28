#!/usr/bin/env bash
# 把环境配置灌入 SSM Parameter Store（唯一事实源）：
#   /css/<env>/backend.env  ← 工作区 deploy-env/<env>/backend.env  （SecureString, Advanced 层）
#   /css/<env>/frontend.env ← 工作区 deploy-env/<env>/frontend.env （SecureString, Standard 层）
# （deploy-env/ 2026-07-28 由 CSS_backend-main/deploy/env 迁出，与两个代码仓库同级）
# 用法: ./put-params.sh <test|uat|prod>
# 注意: Windows git-bash 下 aws.exe 读中文路径/编码会炸——本脚本先拷到 ASCII 临时路径并设 UTF-8。
set -euo pipefail

ENV_NAME="${1:?用法: put-params.sh <test|uat|prod>}"
case "$ENV_NAME" in test|uat|prod) ;; *) echo "环境必须是 test|uat|prod"; exit 1 ;; esac
REGION="us-east-1"
export AWS_CLI_FILE_ENCODING=UTF-8
# git-bash(MSYS) 会把 /css/... 开头的参数误转成 Windows 路径,禁用该转换(Linux 上无影响)
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../../../deploy-env/$ENV_NAME"
[ -f "$SRC_DIR/backend.env" ]  || { echo "缺 $SRC_DIR/backend.env（以同目录 example 为底稿填值）"; exit 1; }
[ -f "$SRC_DIR/frontend.env" ] || { echo "缺 $SRC_DIR/frontend.env"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMPF="$(cygpath -m "$TMP")"; else TMPF="$TMP"; fi
cp "$SRC_DIR/backend.env" "$TMP/be.env"
cp "$SRC_DIR/frontend.env" "$TMP/fe.env"

aws ssm put-parameter --region "$REGION" --name "/css/$ENV_NAME/backend.env" \
  --type SecureString --tier Advanced --overwrite --value "file://$TMPF/be.env" >/dev/null
aws ssm put-parameter --region "$REGION" --name "/css/$ENV_NAME/frontend.env" \
  --type SecureString --tier Standard --overwrite --value "file://$TMPF/fe.env" >/dev/null

LEN=$(aws ssm get-parameter --region "$REGION" --name "/css/$ENV_NAME/backend.env" --with-decryption \
  --query 'length(Parameter.Value)' --output text | tr -d '\r')
echo "===== 已灌入 /css/$ENV_NAME/{backend,frontend}.env（backend 长度 $LEN 字符） ====="
echo "生效: 后端变量重跑 deploy job 即可；前端 VITE_* 需重新构建镜像"
