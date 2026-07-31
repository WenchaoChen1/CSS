# 03-本地构建推送镜像 —— Windows 开发机的镜像构建/推送工具（CI 的兜底）

> **主链路是 CI**：push 代码到 `test`/`uat`/`main` 分支，GitHub Actions 自动构建并推送（tag `<env>-vN`）。
> 本目录脚本用于三种场景：**CI 挂了应急**、**首次给新环境灌镜像**、**本机调试构建产物**。
> 两个脚本与 CI 完全同源（都调 Backend 仓库 `deploy/compose/*.yml` 的构建定义），不存在"手动打的和 CI 不一样"。

## 两个脚本

| 脚本 | 做什么 | 什么时候用 |
|------|--------|-----------|
| `build-images.sh <env> [tag] [scope]` | **只构建、不推送**（产物留在本机 Docker） | 本机验证构建能过 / 先打包后审再推 |
| `push-ecr.sh <env> [tag]` | **构建 + 推送到该环境的 ECR**（内部：渲染配置 → ECR 登录 → 构建 → 双 tag 推送） | CI 挂了 / 新环境首次灌镜像 |

## 不同环境怎么推

每个环境是**独立的 ECR 仓库前缀**（`test/css-*`、`uat/css-*`、`prod/css-*`），推错环境不会互相污染：

```bash
cd docs/新aws账号/03-本地构建推送镜像

# ---- test ----
bash push-ecr.sh test                  # tag 自动 = test-manual-<后端git sha7>
# ---- uat ----
bash push-ecr.sh uat                   # uat-manual-<sha7>
bash push-ecr.sh uat uat-manual2       # 或显式 tag
# ---- prod（谨慎：正式流程应走 CI 的 main 分支 + 手动 Run workflow）----
bash push-ecr.sh prod

# ---- 只构建不推（任意环境）----
bash build-images.sh test              # 6 个后端镜像
bash build-images.sh test '' all       # 后端 + 前端
```

**tag 约定**：CI 用 `<env>-vN`（不可变版本号，回滚依据）；本地手动用 `<env>-manual-<sha7>`（push-ecr）
或 `<env>-local-<sha7>`（build-images），刻意与 CI 序列分开。push 时同时更新 `<env>` 浮动 tag，
EC2 的 compose 默认拉浮动 tag。

**本地 dev 环境的镜像**：不走本目录——用 `CSS_backend-main\deploy\windows\本地dev.ps1 build`
（dev 栈在本机 compose 里直接 build，不推 ECR）。

## Windows 前置

- Docker Desktop 运行中（`docker version` 能通）；
- aws cli 凭证有该环境 ECR push + `/css/<env>/*` 参数读取权限（push-ecr 会从 Parameter Store 渲染配置，
  回退到工作区 `deploy-env/<env>/` 底稿）；
- 前端构建需要同级存在 `../CSS_frontend-main`（工作区默认布局）；
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
