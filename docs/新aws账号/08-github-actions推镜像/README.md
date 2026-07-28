# 08-github-actions推镜像 —— GitHub Actions 配置与使用手册（含一键配置脚本）

> GitHub Actions 自动推镜像/部署的**完整手册**：脚本用途、页面怎么找、配置什么、日常怎么用、出错怎么查。
> workflow 本体在两仓库 `.github/workflows/cicd.yml`（名字 **CICD**，push `test`/`uat`/`main` 自动：构建 → 双 tag 推每环境独立 ECR 仓库——不可变版本号 `<env>-vN` + 浮动 `<env>`）。
> ⚠️ **现状（2026-07-28）：CI 只推镜像**——migrate/deploy job 已在 workflow 里注释；部署 = 手动执行 [`../09-ssm-run-command/deploy-env.sh <env>`](../09-ssm-run-command/README.md)。本文涉及"CI 自动部署/SSM 部署"的流程描述均为**恢复注释后的目标态**。
> 具体值（ARN/registry/标签）统一见 [../../环境/配置速查.md](../../环境/配置速查.md)。以下"仓库页"指 `github.com/Chain-Serve-Solutions/Chain-Service-Solutions-Backend`（Frontend 仓库同样操作一遍）。

## 〇、本文件夹的脚本

`setup-github-actions.sh <backend|frontend|all>`：用 gh CLI 一键做下面 §1 的仓库配置（Environments + production 审批人；4 个 Variables 自 2026-07-28 起已写死进 workflow，脚本中该步骤变为冗余无害）。前置 `winget install GitHub.cli` + `gh auth login`（charles221900）。不装 gh 就照 §1 手动点页面，效果一样。

## 一、需要配置的页面（一次性）

> **2026-07-28 简化**：原来的 4 个 Repository variables（角色 ARN×3 + ECR 地址）为非敏感固定值，**已直接写死进两个仓库的 workflow 文件**，①不再需要配置。剩下真正必须手动做的只有 ②production 审批人（否则 prod 部署没有人工闸）和 ③邮箱验证（仅影响头像）。
> ⚠️ 推镜像**仍然需要 IAM 权限**：workflow 经 OIDC 用 GitHub 签发的身份证明向 AWS 换取几分钟过期的临时凭证（角色信任策略只认这两个仓库的对应分支，`07-iam` 配置）；写死的 ARN 只是角色名字，权限全在 AWS 侧控制。

### ① Repository variables（已免配，留档说明）

**怎么找**：仓库页 → 顶部 **Settings** 标签 → 左侧栏 **Secrets and variables** → **Actions** → 切到 **Variables** 页签。
直达 URL：`https://github.com/Chain-Serve-Solutions/<仓库名>/settings/variables/actions`

原需配置 `AWS_ROLE_ARN_TEST/UAT/PROD`、`ECR_REGISTRY` 四个变量（值见配置速查 §2），现已写死于 workflow `env:` 段与 `role-to-assume`，无需操作。这四个都不是密钥——OIDC 方案下 GitHub 不存任何 AWS 密钥。

### ② production 生产闸（2026-07-28 起：手动触发模式，无需页面配置）

> **实测限制**：GitHub Free 计划的**私有仓库不支持环境审批**（Configure 页没有 Required reviewers 区域）。因此生产闸改为 **workflow 内置的手动触发模式**：
> - push `main` → 只跑 lint + 构建镜像（`prod-vN` 推入 ECR，随时可发）；**不会自动部署生产**；
> - 真要部署生产 = 人为去 Actions → CICD → **Run workflow** → environment 选 `prod` →（可选 image_tag）→ 运行——这一步就是人工审批。
> 加上 main 分支已配"需 PR 才能合并"，代码闸 + 部署闸齐全。若将来升级 GitHub Team（$4/人/月），可改回环境 Required reviewers 模式。

**Environments 页面维护**（两仓库）：workflow 用的环境名是 `test`/`uat`/`production`（自动创建，无需配置规则）；如果手动建过 `main` 环境请删除（名字对不上，避免混淆）。Environment secrets/variables 全部留空——值已写死进 workflow。
（可选加固：`production` 环境的 Deployment branches and tags 改为 Selected branches → 只允许 `main`。）

### ③ 提交邮箱验证（charles221900 个人账号，一次）

**怎么找**：右上角头像 → **Settings** → 左侧栏 **Emails**。直达 URL：`https://github.com/settings/emails`
**配置什么**：**Add email address** 填 `charles@shinypathway.com` → 去邮箱点验证链接。没验证的话提交只显示纯文本 charles、不挂头像。

## 二、日常使用的可视化页面

### 看流水线 / 审批 / 重跑

**怎么找**：仓库页 → 顶部 **Actions** 标签 → 左侧选 **CICD** workflow → 点某次 run。
- **看本次版本号**：build-push job 日志里的镜像 tag（`<env>-vN`，N=run 序号），回滚时要用；
- **审批 prod**：run 页面出现黄色 "Review deployments" → 点它 → 勾选 `production` → **Approve and deploy**；
- **重跑**：run 页面右上 **Re-run all jobs**（配置错误修好后用）；
- **看失败原因**：点红叉的 job → 展开红色步骤；deploy job（现已注释，恢复后）的日志里包含 EC2 端 deploy.sh 的完整输出——现阶段部署输出看手动 `deploy-env.sh` 的终端回显 / SSM Run Command 历史。

### 回滚 / 手动指定环境部署

**怎么找**：Actions → CICD → 右侧 **Run workflow** 下拉（灰色按钮）。
**填什么**：Branch 选对应分支 → `environment` 选目标环境 → `image_tag` 填要回退到的不可变版本 tag（`<env>-vN`，如 `test-v12`，从 ECR 控制台或上次成功 run 的日志里查）→ **Run workflow**。填了 tag 会跳过构建直接部署旧镜像；prod 仍要过审批。
⚠️ 现阶段 deploy job 注释中，Run workflow 只会重推镜像不会部署——回滚实际执行 `../09-ssm-run-command/deploy-env.sh <env> all <env>-vN`。

### 推送结果（AWS 侧）

ECR 仓库 Images 页签看新 tag：`https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1`（每环境独立仓库 `<env>/css-xxx`，`<env>-vN` 与浮动 `<env>` 双 tag 指向同一 digest；lifecycle 每仓库保留最近 5 个镜像）。

## 三、发布操作（命令行侧）

> 现阶段下表的 push 只触发**推镜像**（`<env>-vN`）；推完后手动 `bash docs/新aws账号/09-ssm-run-command/deploy-env.sh <env>` 完成部署。

| 目标 | 命令 |
|------|------|
| 发 test | `git push neworg test` |
| 发 uat | `git checkout uat && git merge test && git push neworg uat` |
| 发 prod | `git checkout main && git merge uat && git push neworg main` → 去 Actions 审批（恢复 deploy job 后） |
| 同步老仓库 | 先合到 `upstream-sync`（不触发部署），验证后再进 test——见 [../../环境/cicd-操作手册.md](../../环境/cicd-操作手册.md) |

## 四、workflow 文件本身（要改流水线时）

位置：两仓库各自的 `.github/workflows/cicd.yml`（Backend 还有 `deploy/aws/{build-push.sh,ssm-run.sh}`；Frontend 有 `.github/scripts/ssm-run.sh`）。job 结构：lint（仅检查本次改动的文件，与 pre-commit 语义一致）→（unit-test/typecheck 观察模式）→ build-push →（**已注释**）migrate（仅 Backend，uat/prod 先快照）→（**已注释**）deploy——取消注释即恢复自动部署。改动走正常分支流程，**改 workflow 也要经 test 验证再晋级**。

## 五、常见失败对照

| 现象 | 原因/处理 |
|------|-----------|
| configure-aws-credentials 报 Not authorized | 分支不在角色信任策略里（只信 test/uat/main 与三个 Environment，见 `07-iam`） |
| Parameter not found | 该环境的 `/css/<env>/*.env` 还没灌入 Parameter Store（`11-parameter-store`） |
| ECR push 报 not authorized/not exist | 目标环境的 `<env>/css-xxx` 仓库未建（`02-ecr`）或角色权限与前缀不符 |
| ssm-run 报没有 Online 实例 | 见 [../09-ssm-run-command/README.md](../09-ssm-run-command/README.md) |
| deploy 冒烟失败 | 看 job 日志里 deploy.sh 输出定位是哪个栈没起来 |
| prod 一直转圈 | 在等审批：run 页面 Review deployments |
