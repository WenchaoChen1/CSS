# 生产 CI/CD：GitHub Actions 触发打包与部署

> 生产环境的构建（打镜像推 ECR）与部署（拉起/更新服务）统一由 **GitHub Actions** 触发驱动，取代现有的 GitLab CI 与本机手动 `打镜像推ECR.ps1` + SSH 手动 `deploy.sh`。方案一（单机）与方案二（Serverless）共用本 CI/CD 设计，仅"部署动作"不同。
> 只出方案，不创建资源、不落 workflow 文件。编制日期：2026-07-23。

---

## 1. 为什么用 GitHub Actions

- 代码已在 **GitHub**（交接记忆：GitHub `main` 是唯一可用来源），CI/CD 与代码同源，触发直观。
- 原 GitLab CI 有多处审计问题需要规避（并非把 GitLab 流程照搬）：
  - 🔴 前端 CI `cat $DOT_ENV` 把 `.env`（含全部密钥）打进 job 日志（审计 04 号 `fe:.gitlab-ci`）；
  - 🟠 自托管 gitlab-runner 挂宿主 `docker.sock`、且与业务同机（审计 02§5-2）；
  - 🟠 密钥靠 GitLab File 变量 + 明文 `.env` 流转，无 Secrets Manager。
- GitHub Actions 用 **OIDC 免长期 AWS 密钥** + **Environments 审批** + **托管 runner（不碰业务机）**，天然规避上述问题。

---

## 2. 核心原则

| 原则 | 做法 | 规避的审计问题 |
|------|------|----------------|
| 免静态 AWS 密钥 | GitHub OIDC → 假设 AWS IAM 角色（`aws-actions/configure-aws-credentials`，`permissions: id-token: write`），GitHub 不存长期 AK/SK | IAM 静态 key 卫生差 |
| runner 不碰业务机 | 构建在 GitHub 托管 runner（`ubuntu-latest`）；部署经 **AWS SSM** 下发到 EC2，**不 SSH、不在 EC2 上跑 runner、不挂 docker.sock** | 02§5-2 / 03§3-4 |
| 密钥不进日志 | 构建期变量走 GitHub Environment secrets（自动脱敏）；**禁止 `cat`/`echo` 环境变量**；运行时应用密钥留 **AWS Secrets Manager**，不进 GitHub、不进日志 | 前端 `.env` 泄露 / 05§ 密钥流转 |
| 生产要审批 | 部署到 `production` 用 **GitHub Environments + Required reviewers**（人工点批）取代 GitLab 的 `when: manual` | 误发 |
| 镜像不可变 | 生产镜像 tag 用 `vX.Y.Z` / git sha（不可变），ECR 开镜像扫描 + 生命周期保留 | 02§5-8 可变 tag/无回滚 |
| 迁移解耦 + 快照 | 迁移是独立 job/审批，执行前先打 **RDS 快照** + 核对 `alembic_version` | 02§5-1 迁移卡发布 |

---

## 3. 触发策略

| 事件 | 触发的流程 | 目标环境 |
|------|-----------|----------|
| push 到 `main` | 构建候选镜像（tag=git sha）+ 自动部署到 test/uat（可选） | test / uat |
| push git tag `v*`（如 `v1.4.0`） | 构建**不可变生产镜像** | 生产候选 |
| `workflow_dispatch`（手动，选 environment + tag） | 部署到指定环境（生产需审批） | test / uat / **prod** |

> 生产发布走"打 tag → 构建 → 手动 dispatch 部署 prod（Environment 审批）"，避免 push 即上生产。原 GitLab `deployment/<env>` 分支触发模型不再用于生产。

---

## 4. 流水线结构（build → migrate → deploy）

```
GitHub Actions（托管 runner）
  ┌─ build-push ─────────────────────────────────────────────┐
  │ 1. checkout（后端 + 前端）                                  │
  │ 2. OIDC 假设 AWS 角色（configure-aws-credentials）          │
  │ 3. amazon-ecr-login                                        │
  │ 4. buildx build+push 7 镜像到 ECR（不可变 tag，开扫描）      │
  │    - 后端 6 持有者：app/nginx/sms_sender/email_sender/      │
  │      ai_assistant/ocr-migrator（app 镜像复用 4 服务、        │
  │      catalog-ocr 复用 3 服务）                              │
  │    - 前端 1：css-frontend/app（VITE_* 作为 build-arg 注入，   │
  │      来自 Environment secrets，不打印）                      │
  └────────────────────────────────────────────────────────────┘
                          │ needs
  ┌─ migrate（prod 独立 job + 审批）───────────────────────────┐
  │ 5. OIDC 角色 → 先打 RDS 快照 → 经 SSM 跑 alembic upgrade    │
  │    head（方案一：deploy.sh prod migrate；方案二：ecs        │
  │    run-task migrate）；生产库源自快照时先核对 alembic_version │
  └────────────────────────────────────────────────────────────┘
                          │ needs
  ┌─ deploy（environment: production，Required reviewers 审批）─┐
  │ 6a. 方案一（单机）：aws ssm send-command →                  │
  │     /opt/css/bin/deploy.sh prod deploy（ECR登录+pull+up）    │
  │ 6b. 方案二（Serverless）：aws ecs update-service            │
  │     --force-new-deployment（或 CodeDeploy 蓝绿切流）         │
  │ 7. 健康检查（ALB target 健康 / ecs 服务稳定）→ 失败告警回滚   │
  └────────────────────────────────────────────────────────────┘
```

- **构建**沿用现有构建逻辑（等价 `部署包/bin/打镜像推ECR.ps1` / `deploy/aws/build-push.sh` 的 compose build+push），只是搬到 GitHub 托管 runner 上跑，用 `docker/build-push-action` 或直接 compose。
- **部署**方案一复用 EC2 上已有的 `/opt/css/bin/deploy.sh`，由 GitHub Actions 经 **SSM Run Command** 远程触发（EC2 实例角色需 `AmazonSSMManagedInstanceCore` + ECR 只读）；方案二用 `ecs update-service` / CodeDeploy。

---

## 5. 密钥与配置分层

| 类别 | 存放位置 | 用途 |
|------|----------|------|
| AWS 访问（无长期 key） | GitHub OIDC → IAM 角色（`role-to-assume`），按 Environment 区分 test/uat/prod 角色 | 登录 ECR、发 SSM、调 ECS |
| 构建期变量（前端 `VITE_*`、`IMAGE_TAG`） | GitHub **Environment** variables/secrets | 前端镜像 build-arg（`VITE_X_API_KEY` 必须等于后端 `API_KEY`） |
| 运行时应用密钥（JWT_SECRET/DB 口令/Twilio/OpenAI/SMTP/Gemini…） | **AWS Secrets Manager**（不进 GitHub） | 容器/任务启动时注入；`.env` 在 EC2 由 Secrets 生成或 SSM Parameter Store 拉取，绝不打印 |
| EC2 上部署文件 | 仍是 `/opt/css/{compose,env/prod/backend.env,bin/deploy.sh}`；`backend.env` 由 Secrets 渲染，chmod 600 | 方案一部署 |

> 关键：`API_KEY==VITE_X_API_KEY`、`CATALOG_OCR_API_KEY==OCR_API_KEY` 两处耦合仍需保证；这两个值分别在"前端构建期 Environment secret"与"后端运行时 Secrets Manager"里保持一致。

---

## 6. 示例 workflow 骨架（说明用，非落地文件）

```yaml
# .github/workflows/deploy.yml —— 骨架，落地阶段再细化
name: build-and-deploy
on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      environment: { description: 目标环境, type: choice, options: [test, uat, prod] }
permissions:
  id-token: write        # OIDC
  contents: read
jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}   # OIDC，无静态 key
          aws-region: us-east-1
      - uses: aws-actions/amazon-ecr-login@v2
      - name: build & push (7 images)
        run: ./deploy/aws/build-push.sh ${{ inputs.environment || 'prod' }} ${{ github.ref_name }}
        # VITE_* 作为 build-arg 由 env 注入，禁止 echo/cat
  migrate:
    needs: build-push
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment || 'prod' }}   # 生产环境含 Required reviewers 审批
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}, aws-region: us-east-1 }
      - name: RDS 快照 + 迁移（经 SSM，不 SSH）
        run: |
          aws rds create-db-snapshot ...          # 先快照
          aws ssm send-command --document-name AWS-RunShellScript \
            --targets Key=tag:Name,Values=css-prod \
            --parameters 'commands=["/opt/css/bin/deploy.sh prod migrate"]'
  deploy:
    needs: migrate
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment || 'prod' }}
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with: { role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}, aws-region: us-east-1 }
      - name: 部署（方案一：SSM 触发 deploy.sh / 方案二：ecs update-service）
        run: |
          aws ssm send-command --document-name AWS-RunShellScript \
            --targets Key=tag:Name,Values=css-prod \
            --parameters 'commands=["/opt/css/bin/deploy.sh prod deploy"]'
          # 方案二替换为: aws ecs update-service --cluster css-prod --service ... --force-new-deployment
```

---

## 7. 从现状迁移

- **保留 EC2 上的 `deploy.sh` 与三栈 compose 不变**——GitHub Actions 只是"远程触发器"，部署逻辑仍是那套已跑通的脚本，改动面小、可回退。
- 现 GitLab CI（`.gitlab-ci.yml`）：生产切到 GitHub Actions 后可停用；非生产（dev/test）可暂留 GitLab 或一并迁 GitHub（推荐统一，减少两套流水线维护）。
- 一次性准备（落地阶段）：① 在 AWS 建 GitHub OIDC provider + 各环境部署角色（最小权限：ECR push/pull、SSM send-command、ECS 更新、RDS 快照）；② EC2 实例角色加 `AmazonSSMManagedInstanceCore`；③ GitHub 建 `test/uat/production` Environments，`production` 配 Required reviewers；④ 运行时密钥入 Secrets Manager；⑤ 写 `.github/workflows/*.yml`。

---

## 8. 规避审计问题小结

| 审计问题 | GitHub Actions 方案的对应 |
|----------|---------------------------|
| 前端 CI 打印 `.env` 到日志 | Environment secrets 自动脱敏 + 禁止 `cat/echo`；运行时密钥不进 CI |
| runner 挂 docker.sock、与业务同机 | 托管 runner 构建 + SSM 远程部署，业务机无 runner、不开 22 |
| 密钥无 Secrets Manager、明文 `.env` 流转 | 运行时密钥进 Secrets Manager；GitHub 只存构建期变量 |
| 静态 AWS AK/SK | OIDC 假设角色，GitHub 零长期 AWS 密钥 |
| 可变镜像 tag、无回滚 | tag `vX.Y.Z` 不可变 + ECR 扫描/保留 + 旧 tag 回滚 |
| 每次 down+up 停机、迁移卡发布 | 迁移独立 job + 快照；方案二 ECS 滚动/蓝绿零停机 |
| 误发生产 | Environments Required reviewers 人工审批 |
