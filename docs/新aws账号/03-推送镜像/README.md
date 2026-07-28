# 03-推送镜像 —— 本机手动构建并推送 7 个镜像到 ECR

手动推镜像工具（**CI/CD 是主链路**，本脚本用于 CI 挂了 / 首次灌镜像 / 本机调试）。实现：环境配置从 **SSM Parameter Store** 渲染（回退工作区根 `deploy-env/<env>/` 已有文件）→ ECR 登录 → 委托 Backend 仓库 `deploy/aws/build-push.sh`（与 CI **同一套构建定义**）→ 双 tag 推送（不可变 tag 缺省 `<env>-manual-<sha7>`，与 CI 的版本号 `<env>-vN` 序列分开 + `<env>` 浮动）。

## 怎么用

```bash
# 前置：Docker Desktop 运行中；aws 凭证有 ECR push + 本环境参数读取权限；
#       前端构建需要同级存在 ../CSS_frontend-main（工作区默认布局）
bash docs/新aws账号/03-推送镜像/push-ecr.sh test            # tag 默认 test-manual-<后端 git sha7>
bash docs/新aws账号/03-推送镜像/push-ecr.sh uat uat-manual1  # 显式 tag
```

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 推上去的镜像与双 tag | ECR 仓库 **Images** 页签：`https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1` → 点仓库（如 `test/css-backend/app`）→ 应看到 `<env>-manual-<sha7>`（手动）或 `<env>-vN`（CI）和 `<env>` 指向同一 digest |
| 本机构建产物 | Docker Desktop → Images 列表 |
| CI 的同款推送记录 | GitHub 仓库 → Actions → cicd → build-push job 日志 |

## 状态 / 注意

- 与 CI 用的构建定义完全同源（Backend 仓库 `deploy/compose/*.yml`），不存在"手动推的镜像和 CI 不一样"；
- 每仓库 lifecycle 只保留最近 5 个镜像（见 `02-ecr`），手动多推会挤掉旧版本——留意回滚窗口；
- 构建平台默认 `linux/amd64`（与 EC2 一致）。
