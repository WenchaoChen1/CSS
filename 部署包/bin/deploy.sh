#!/usr/bin/env bash
# AWS EC2 部署脚本(在目标环境的 EC2 上执行)—— 三栈拆分:infra / backend / frontend
# 部署源外置版:compose 在 compose/,env 在 env/<env>/backend.env,EC2 上不需要项目源码。
# 用法: ./bin/deploy.sh <test|uat|prod> [action] [stack]
#   action: deploy(默认,=ECR登录+pull+up) | up | down | pull | migrate | ps | logs | restart | pytest
#   stack : all(默认) | infra | backend | frontend   —— 只动指定栈,其余栈不受影响
# 例:
#   ./bin/deploy.sh test deploy            # 首次:三栈全部拉起(infra->backend->frontend)
#   ./bin/deploy.sh test deploy backend    # 只发布后端(前端/中间件不动)
#   ./bin/deploy.sh test logs backend
# 三栈是独立 compose 项目(css-<env>-infra/-backend/-frontend),
# 靠共享 docker 网络 css-<env>-net 互访(本脚本自动创建)。
# ⚠️ prod 的 migrate:生产库若源自原团队快照,先人工核对 alembic_version(见 CLAUDE.md)。
set -euo pipefail

ENV_NAME="${1:?用法: $0 <test|uat|prod> [action] [stack]}"
ACTION="${2:-deploy}"
STACK="${3:-all}"
case "$ENV_NAME" in test|uat|prod) ;; *) echo "环境必须是 test|uat|prod"; exit 1 ;; esac
case "$STACK" in all|infra|backend|frontend) ;; *) echo "stack 必须是 all|infra|backend|frontend"; exit 1 ;; esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ENV_FILE="env/${ENV_NAME}/backend.env"
[ -f "$ENV_FILE" ] || { echo "缺少 $ENV_FILE(参考 env/uat/backend.env.example 填真实值)"; exit 1; }
export ENV_FILE

# || true:键缺失时返回空串而不是被 set -e 杀掉;tr -d '\r':容忍从 Windows 拷来的 CRLF
getvar() { { grep -E "^$1=" "$ENV_FILE" || true; } | tail -1 | cut -d= -f2- | tr -d '"\r' ; }
AWS_REGION="$(getvar AWS_REGION)"
ECR_REGISTRY="$(getvar ECR_REGISTRY)"
[ -n "$AWS_REGION" ] && [ -n "$ECR_REGISTRY" ] || { echo "$ENV_FILE 缺 AWS_REGION / ECR_REGISTRY"; exit 1; }

NET="css-${ENV_NAME}-net"

# 生成某个栈的 compose 参数(独立项目名 + 各自的 compose 文件)
compose_args() {  # $1 = infra|backend|frontend
  local args=(-p "css-${ENV_NAME}-$1" --project-directory . --env-file "$ENV_FILE" -f "compose/$1.yml")
  # kafka-ui(2FA 看码)在 infra 的 tools profile:test/uat 默认启;prod 需 TOOLS=1
  if [ "$1" = "infra" ] && { [ "$ENV_NAME" != "prod" ] || [ "${TOOLS:-0}" = "1" ]; }; then
    args+=(--profile tools)
  fi
  printf '%s\n' "${args[@]}"
}

# 该 action 实际作用的栈列表(all 按依赖顺序;down 反序)
stacks_for() {
  case "$STACK" in
    all)  if [ "$1" = "down" ]; then echo "frontend backend infra"; else echo "infra backend frontend"; fi ;;
    *)    echo "$STACK" ;;
  esac
}

ecr_login() {
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$ECR_REGISTRY"
}

ensure_network() { docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET"; }

run_compose() {  # $1 = stack, 其余 = compose 子命令
  local stack="$1"; shift
  local args; mapfile -t args < <(compose_args "$stack")
  docker compose "${args[@]}" "$@"
}

case "$ACTION" in
  deploy)  ecr_login; ensure_network
           for s in $(stacks_for deploy); do
             echo "==== [$s] pull + up ===="
             run_compose "$s" pull
             run_compose "$s" up -d --remove-orphans
           done ;;
  pull)    ecr_login; for s in $(stacks_for pull); do run_compose "$s" pull; done ;;
  up)      ensure_network; for s in $(stacks_for up); do run_compose "$s" up -d --remove-orphans; done ;;
  down)    for s in $(stacks_for down); do run_compose "$s" down; done ;;
  restart) for s in $(stacks_for down); do run_compose "$s" down; done
           ensure_network
           for s in $(stacks_for up); do run_compose "$s" up -d; done ;;
  ps)      for s in $(stacks_for ps); do echo "==== [$s] ===="; run_compose "$s" ps; done ;;
  logs)    [ "$STACK" = "all" ] && { echo "logs 请指定栈: $0 $ENV_NAME logs <infra|backend|frontend>"; exit 1; }
           run_compose "$STACK" logs -f --tail 100 ;;
  migrate) ecr_login; ensure_network
           run_compose backend run --rm --no-deps app alembic upgrade head ;;
  pytest)  # 仅 test:测试夹具会写库,禁止打到 uat/prod 的真实数据
           [ "$ENV_NAME" = "test" ] || { echo "pytest 仅允许 test 环境(会写数据库)"; exit 1; }
           ecr_login; ensure_network
           run_compose backend run --rm app pytest -n logical --reruns 2 ;;
  *)       echo "用法: $0 <test|uat|prod> [deploy|up|down|pull|migrate|ps|logs|restart|pytest] [all|infra|backend|frontend]"; exit 1 ;;
esac
