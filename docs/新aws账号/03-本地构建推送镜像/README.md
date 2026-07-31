# 03-本地构建推送镜像 —— Windows 开发机的镜像构建/推送工具（CI 的兜底）

> **主链路是 CI**：push 代码到 `test`/`uat`/`main` 分支，GitHub Actions 自动构建并推送（tag `<env>-vN`）。
> 本目录脚本用于三种场景：**CI 挂了应急**、**首次给新环境灌镜像**、**本机调试构建产物**。
> 两个脚本与 CI 完全同源（都调 Backend 仓库 `deploy/compose/*.yml` 的构建定义），不存在"手动打的和 CI 不一样"。

## 脚本清单

每个环境是**独立的 ECR 仓库前缀**（`test/css-*`、`uat/css-*`、`prod/css-*`），推错环境不会互相污染。脚本在本目录下运行（`cd docs/新aws账号/03-本地构建推送镜像`）。

### `build-images.sh` — 本地只构建、不推送镜像（产物留在本机 Docker，规格与推送版完全一致）

```bash
./build-images.sh <test|uat|prod> [tag] [backend|frontend|all]   # tag 缺省 <env>-local-<后端git sha7>；scope 缺省 backend
./build-images.sh test                    # 构建 6 个后端镜像（本机验证构建能过）
./build-images.sh test '' all             # 后端 + 前端（需同级存在 ../CSS_frontend-main）
./build-images.sh uat uat-local1 frontend # 显式 tag，只构建前端
```

前置：Docker Desktop 运行中；工作区根 `deploy-env/<env>/backend.env` 存在（提供 ECR_REGISTRY 等构建变量，缺失时用最小内置值，仅影响镜像名前缀）。构建完成后可直接用 `push-ecr.sh <env> <同一tag>` 推送。

### `push-ecr.sh` — 本机手动构建并推送 7 个镜像到该环境 ECR（渲染配置 → ECR 登录 → 构建 → 双 tag 推送；CI 的备用/首次灌仓通道）

```bash
./push-ecr.sh <test|uat|prod> [tag]    # tag 缺省 <env>-manual-<后端git sha7>
./push-ecr.sh test                     # CI 挂了应急 / 新环境首次灌镜像
./push-ecr.sh uat uat-manual2          # 显式 tag
./push-ecr.sh prod                     # 谨慎：正式流程应走 CI 的 main 分支 + 手动 Run workflow
```

前置：Docker Desktop 运行中；aws cli 凭证有该环境 ECR push 与 `/css/<env>/*` 参数读取权限（配置优先从 SSM Parameter Store 渲染，回退工作区 `deploy-env/<env>/` 已有文件）；前端构建需同级存在 `../CSS_frontend-main`。

**tag 约定**：CI 用 `<env>-vN`（不可变版本号，回滚依据）；本地手动用 `<env>-manual-<sha7>`（push-ecr）
或 `<env>-local-<sha7>`（build-images），刻意与 CI 序列分开。push 时同时更新 `<env>` 浮动 tag，
EC2 的 compose 默认拉浮动 tag。

**本地 dev 环境的镜像**：不走本目录——用 `CSS_backend-main\deploy\windows\本地dev.ps1 build`
（dev 栈在本机 compose 里直接 build，不推 ECR）。

## Windows 前置

- 各脚本前置见上方脚本清单；共同要求：Docker Desktop 运行中（`docker version` 能通）；
- 构建平台固定 `linux/amd64`（与 EC2 一致，Windows 上无需额外设置）。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 推上去的镜像与双 tag | ECR 控制台 → 仓库（如 `test/css-backend/app`）→ Images：`https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1` |
| 本机构建产物 | Docker Desktop → Images（`docker images \| grep test/`） |
| CI 的同款推送记录 | GitHub 仓库 → Actions → cicd → build-push job 日志 |

## 注意

- 每仓库 lifecycle 只保留最近 **5 个**镜像（Terraform `<env>/ecr` stack 管理），手动多推会挤掉旧版本——留意回滚窗口；
- 推 prod 前三思：正式发布应走 CI（main 分支构建 + 手动触发部署），本脚本只是应急通道。
