#!/usr/bin/env bash
# 云上应用机构建并推送镜像 —— 本机无 Docker 时的构建通道（support-ref 无 CI，正规重建走本脚本）。
# 流程：本地渲染环境配置（同 push-ecr.sh）→ 打包前后端源码 + deploy-env/<env> → 临时 S3 中转
#       （预签名 URL 下发，对象与桶用完即删）→ 本地签发 ECR push token 写入 SSM SecureString
#       （实例角色只有 ECR pull——2026-08-07 实测 push denied；token 以调用者身份鉴权，有效 12h，用完即删）
#       → SSM Run Command 在目标环境应用机上解包、docker login、跑仓库 deploy/aws/build-push.sh <env> <tag> <scope>
#       （与 CI/push-ecr.sh 同一套构建定义，双 tag：<tag> + <env> 浮动）。
# 用法: ./remote-build-push.sh <test|uat|support-ref|support-demo|prod> [tag] [backend|frontend|all]
#   tag   缺省 <env>-manual-<后端 git sha7>；scope 缺省 all（7 镜像）
# 前置: aws cli 凭证有 ECR push / SSM / S3 / 目标环境参数读取权限；目标机 SSM Online、
#       docker compose ≥2.17（frontend 构建用 additional_contexts/dockerfile_inline，2026-08-11 实测 v5.4.0）。
# 注意: 构建在业务机上跑（2vCPU），已设 COMPOSE_PARALLEL_LIMIT=1 串行构建防 OOM；全量约 20-60 分钟。
#       构建完成后仍需部署：bash ../09-远程执行与手动部署/deploy-env.sh <env> all <tag>
set -euo pipefail

# Git Bash 的 MSYS 路径转换会把以 / 开头的 SSM 参数名（/css/...）当路径改写，
# 导致 GetParameter 报 ParameterNotFound、PutParameter 报 ValidationException（2026-08-11 踩坑）。
# 禁用转换的连带约束：① 传给 aws.exe 的本地文件路径必须用相对路径（见 TARBALL/PARAMS_FILE）；
# ② 不能再用 `git -C /c/...`（git.exe 不认 POSIX 绝对路径）——一律子 shell cd 后调 git。
export MSYS_NO_PATHCONV=1
# 中文 Windows 上 aws.exe 默认 GBK 编码 stdout，参数值含 ⚠/中文注释时直接报
# "'gbk' codec can't encode character"（2026-08-11 踩坑），强制 UTF-8
export PYTHONUTF8=1

ENV_NAME="${1:?用法: remote-build-push.sh <test|uat|support-ref|support-demo|prod> [tag] [backend|frontend|all]}"
case "$ENV_NAME" in test|uat|support-ref|support-demo|prod) ;; *) echo "环境必须是 test|uat|support-ref|support-demo|prod"; exit 1 ;; esac
SCOPE="${3:-all}"
REGION="us-east-1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"           # 工作区根 chain-serve/
BACKEND="$ROOT/CSS_backend-main"
ENV_DIR="$ROOT/deploy-env/$ENV_NAME"
mkdir -p "$ENV_DIR"

# python 探测（同 09/run.sh，2026-08-07 修）：必须实际执行验证，防 Windows 商店占位 stub
PY=""
for _cand in python3 python; do
  if "$_cand" -c "1" >/dev/null 2>&1; then PY="$_cand"; break; fi
done
[ -n "$PY" ] || { echo "需要可用的 python"; exit 1; }

# ---------- 1. 渲染环境配置（与 push-ecr.sh 同款 render，含反向覆盖备份） ----------
render() {  # $1=参数名 $2=目标文件
  if aws ssm get-parameter --region "$REGION" --name "$1" --with-decryption \
       --query 'Parameter.Value' --output text > "$2.tmp" 2>/dev/null; then
    if [ -f "$2" ] && ! cmp -s <(tr -d '\r' < "$2") <(tr -d '\r' < "$2.tmp"); then
      cp "$2" "$2.local-bak"
      echo "⚠️ 本地底稿与 Parameter Store 不一致，已备份原文件到 $2.local-bak"
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
ECR_REGISTRY="$(getvar ECR_REGISTRY)"
[ -n "$ECR_REGISTRY" ] || { echo "backend.env 缺 ECR_REGISTRY"; exit 1; }

SHA=$( (cd "$BACKEND" && git rev-parse --short=7 HEAD) 2>/dev/null | tr -d '\r' || echo unknown)
[ "$SHA" != "unknown" ] || { echo "[FAIL] 取不到后端 git sha（构建 tag 依据），中止"; exit 1; }
TAG="${2:-$ENV_NAME-manual-$SHA}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text | tr -d '\r')
BUCKET="css-buildtmp-$ACCOUNT"
KEY="src-$ENV_NAME-$SHA.tgz"
PARAM_TOKEN="/css/$ENV_NAME/tmp-ecr-push-token"

# ---------- 2. 打包源码（排除 .git/node_modules 等；前端构建上下文=整个仓库目录） ----------
# TARBALL 用相对路径：MSYS_NO_PATHCONV=1 后 aws.exe 解析不了 /c/... 形式的绝对路径
cd "$SCRIPT_DIR"
TARBALL=".build-src-$$.tgz"
cleanup() {
  rm -f "$SCRIPT_DIR/$TARBALL" "$SCRIPT_DIR/.ssm-params-$$.json"
  aws s3 rm "s3://$BUCKET/$KEY" --region "$REGION" >/dev/null 2>&1 || true
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1 || true
  aws ssm delete-parameter --region "$REGION" --name "$PARAM_TOKEN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "===== 打包源码 (env=$ENV_NAME tag=$TAG scope=$SCOPE) ====="
tar czf "$TARBALL" -C "$ROOT" \
  --exclude='.git' --exclude='node_modules' --exclude='dist' \
  --exclude='__pycache__' --exclude='.pytest_cache' --exclude='.venv' \
  --exclude='storybook-static' --exclude='coverage' \
  "$(basename "$BACKEND")" CSS_frontend-main "deploy-env/$ENV_NAME"
echo "包大小: $(du -h "$TARBALL" | cut -f1)"

# ---------- 3. S3 中转（临时桶，用完即删——同 05 dbsync 惯例） ----------
aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null \
  || aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3 cp "$TARBALL" "s3://$BUCKET/$KEY" --region "$REGION"
URL=$(aws s3 presign "s3://$BUCKET/$KEY" --region "$REGION" --expires-in 3600 | tr -d '\r')

# ---------- 4. ECR push token 经 SSM SecureString 下发（Intelligent-Tiering 防 4096 上限） ----------
aws ssm put-parameter --region "$REGION" --name "$PARAM_TOKEN" --type SecureString \
  --tier Intelligent-Tiering --overwrite \
  --value "$(aws ecr get-login-password --region "$REGION")" >/dev/null
echo "已下发 ECR push token: $PARAM_TOKEN（结束后自动删除）"

# ---------- 5. SSM Run Command 远程构建（executionTimeout 100 分钟，自带长轮询） ----------
REMOTE_CMD=$(cat <<EOF
set -euo pipefail
mkdir -p /opt/css-build && cd /opt/css-build
rm -rf CSS_backend-main CSS_frontend-main deploy-env src.tgz build.log
curl -fsSL '$URL' -o src.tgz
tar xzf src.tgz && rm -f src.tgz
TOKEN=\$(aws ssm get-parameter --region $REGION --name $PARAM_TOKEN --with-decryption --query Parameter.Value --output text)
echo "\$TOKEN" | docker login --username AWS --password-stdin $ECR_REGISTRY >/dev/null
unset TOKEN
# compose v2.30+ 的 build 要求 buildx >= 0.17（AL2023 自带的太老，2026-08-11 踩坑）——不够就装静态二进制
if ! docker buildx version 2>/dev/null | grep -qE 'v(0\.(1[7-9]|[2-9][0-9])\.|[1-9][0-9]*\.)'; then
  echo "buildx 过旧/缺失，安装 v0.19.3..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-amd64 \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx
  chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
  docker buildx version
fi
export COMPOSE_PARALLEL_LIMIT=1
cd CSS_backend-main
bash deploy/aws/build-push.sh $ENV_NAME $TAG $SCOPE > /opt/css-build/build.log 2>&1 && RC=0 || RC=\$?
echo "===== build.log 尾部 ====="; tail -n 40 /opt/css-build/build.log
docker logout $ECR_REGISTRY >/dev/null 2>&1 || true
docker image prune -f >/dev/null 2>&1 || true
exit \$RC
EOF
)

# 定位目标实例（同 09/run.sh：标签 Environment=css-<env> 且 SSM Online）
IDS=$(aws ssm describe-instance-information --region "$REGION" \
  --filters "Key=tag:Environment,Values=css-$ENV_NAME" \
  --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' --output text | tr -d '\r')
[ -n "$IDS" ] || { echo "[FAIL] 没有 SSM Online 且标签 Environment=css-$ENV_NAME 的实例"; exit 1; }
echo "目标实例: $IDS"

# 参数经临时文件传给 aws.exe（Windows 32K 命令行上限，同 09/run.sh 2026-08-07 修）
PARAMS_FILE=".ssm-params-$$.json"
cd "$SCRIPT_DIR"
CMD="$REMOTE_CMD" "$PY" -c 'import json,os; print(json.dumps({"commands":[os.environ["CMD"]],"executionTimeout":["6000"]}))' > "$PARAMS_FILE"

CMD_ID=$(aws ssm send-command --region "$REGION" \
  --document-name AWS-RunShellScript \
  --instance-ids $IDS \
  --comment "css remote-build $ENV_NAME $TAG" \
  --parameters "file://$PARAMS_FILE" \
  --query 'Command.CommandId' --output text | tr -d '\r')
echo "SSM CommandId: $CMD_ID（构建约 20-60 分钟，每 30s 轮询一次）"

for i in $(seq 1 200); do   # 最长等 100 分钟
  STATUS=$(aws ssm list-command-invocations --region "$REGION" --command-id "$CMD_ID" \
    --query 'CommandInvocations[].Status' --output text | tr -d '\r')
  case "$STATUS" in
    *InProgress*|*Pending*|"") sleep 30 ;;
    *) break ;;
  esac
done

FAILED=0
for id in $IDS; do
  echo "===== 实例 $id 输出 ====="
  aws ssm get-command-invocation --region "$REGION" --command-id "$CMD_ID" --instance-id "$id" \
    --query '{status:Status,stdout:StandardOutputContent,stderr:StandardErrorContent}' --output json \
    | "$PY" -c 'import json,sys; d=json.load(sys.stdin); print(d["stdout"] or ""); print(d["stderr"] or "", file=sys.stderr); sys.exit(0 if d["status"]=="Success" else 1)' \
    || FAILED=1
done
[ "$FAILED" = 0 ] || { echo "[FAIL] 远程构建失败（完整日志在目标机 /opt/css-build/build.log）"; exit 1; }

echo "===== 远程构建推送完成: $SCOPE × {$TAG, $ENV_NAME} ====="
echo "下一步部署: bash $SCRIPT_DIR/../09-远程执行与手动部署/deploy-env.sh $ENV_NAME all $TAG"
