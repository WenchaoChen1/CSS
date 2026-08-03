# 08-github-actions-cicd —— GitHub Actions 配置与使用手册（含一键配置脚本）

> GitHub Actions 自动推镜像/部署的**完整手册**：脚本用途、页面怎么找、配置什么、日常怎么用、出错怎么查。
> workflow 本体在两仓库 `.github/workflows/cicd.yml`（名字 **CICD**，push `test`/`uat`/`main` 自动：构建 → 双 tag 推每环境独立 ECR 仓库——不可变版本号 `<env>-vN` + 浮动 `<env>`）。
> ✅ **现状（2026-07-28 晚）：自动部署已启用**——AWS 侧 RDS/网关机/test+uat 应用机就绪后，migrate 与 deploy job 已取消注释：
> push `test`/`uat` → 构建镜像 + alembic 迁移 + SSM 部署；push `main` → **只构建镜像**，生产部署要人为 Run workflow（就是人工闸）。
> 手动兜底/回滚仍可用 [`../09-远程执行与手动部署/deploy-env.sh <env>`](../09-远程执行与手动部署/README.md)。
> 具体值（ARN/registry/标签）统一见 [../运维访问速查.local.md](../运维访问速查.local.md)。以下"仓库页"指 `github.com/Chain-Serve-Solutions/Chain-Service-Solutions-Backend`（Frontend 仓库同样操作一遍）。

## 脚本清单

### `setup-github-actions.sh` — 用 gh CLI 一键做本手册 §一 的仓库侧配置（写 4 个 Repository variables + 幂等创建 `test`/`uat`/`main` 三个 Environments）

```bash
./setup-github-actions.sh <backend|frontend|all>   # 目标仓库：Backend / Frontend / 两个都配
./setup-github-actions.sh all                      # 典型用法：两仓库一次配齐并列出当前 variables 校验
```

前置：`winget install GitHub.cli` + `gh auth login`（charles221900 账号，GitHub.com → HTTPS → 浏览器登录）。
注意：幂等可重跑无副作用；4 个 Variables 自 2026-07-28 起已写死进 workflow（脚本此步冗余无害），三个环境已手工建齐，**现在跑不跑都一样**——不装 gh 就照 §一 手动点页面，效果相同。`main` 环境的审批人设置仅 GitHub Team+ 计划生效（Free 私有仓库不支持环境审批）。

## 一、需要配置的页面（一次性）

> **2026-07-28 简化**：原来的 4 个 Repository variables（角色 ARN×3 + ECR 地址）为非敏感固定值，**已直接写死进两个仓库的 workflow 文件**，①不再需要配置。
> **2026-07-29 再简化**：GitHub environment 名统一为**与分支同名**——`test` / `uat` / **`main`**（原先生产叫 `production`，是三者中唯一的例外命名，已废弃）。你手工建的三个环境**正好就是这三个名字**，②因此也不用动。真正还需要手动做的只剩 ③邮箱验证（仅影响头像）。
> ⚠️ 推镜像**仍然需要 IAM 权限**：workflow 经 OIDC 用 GitHub 签发的身份证明向 AWS 换取几分钟过期的临时凭证（角色信任策略只认这两个仓库的对应分支，`07-获取应用iam密钥` 配置）；写死的 ARN 只是角色名字，权限全在 AWS 侧控制。

### ① Repository variables（已免配，留档说明）

**怎么找**：仓库页 → 顶部 **Settings** 标签 → 左侧栏 **Secrets and variables** → **Actions** → 切到 **Variables** 页签。
直达 URL：`https://github.com/Chain-Serve-Solutions/<仓库名>/settings/variables/actions`

原需配置 `AWS_ROLE_ARN_TEST/UAT/PROD`、`ECR_REGISTRY` 四个变量（值见配置速查 §2），现已写死于 workflow `env:` 段与 `role-to-assume`，无需操作。这四个都不是密钥——OIDC 方案下 GitHub 不存任何 AWS 密钥。

### ② Environments：**已就位，什么都不用改**（2026-07-29 定稿）

**怎么找**：仓库页 → **Settings** → 左侧 **Environments**。
直达：`https://github.com/Chain-Serve-Solutions/Chain-Service-Solutions-Backend/settings/environments`

**命名规则（2026-07-29 用户拍板）：GitHub environment 名 = 分支名，一律相同。** 即 **`test` / `uat` / `main`** 三个。
原先生产用的 `production` 是三者中唯一的例外命名，已废弃——workflow 的 `environment:` 表达式与 OIDC 信任策略均已改为 `main` 并生效（信任策略现由 css-terraform `css-github` stack 管理；原 07 目录的 create-iam.sh 已删除）。

| 环境名 | 对应分支 | 对应部署环境（`DEPLOY_ENV`） | 你要做什么 |
|--------|----------|------------------------------|------------|
| `test` | `test` | test | **无**，已存在且名字正确 |
| `uat` | `uat` | uat | **无**，已存在且名字正确 |
| `main` | `main` | prod（部署目标仍叫 prod，只有 environment 名叫 main） | **无**，已存在且名字正确 |

> 也就是说：**不用删任何环境、不用新建任何环境、里面不用填任何东西。** 你早先建的三个环境与 workflow 现在引用的名字完全一致。

**里面留空是设计，不是遗漏**：
- **Secrets / Variables 留空** —— AWS 凭证走 OIDC 临时换取，GitHub 不存任何 key；角色 ARN 与 ECR 地址是非敏感固定值，已写死在 workflow 的 `env:` 段与 `role-to-assume`。
- **Protection rules 配不了** —— GitHub Free 的私有仓库不提供 Required reviewers / Wait timer（Configure 页根本没有这块区域，已实测截图确认）。生产闸因此由 **workflow 内部实现**：push `main` 只跑 lint + 构建镜像（`prod-vN` 推 ECR，随时可发），**不会自动部署生产**；真要发布 = 人为去 Actions → CICD → **Run workflow** → environment 选 `prod` →（可选 image_tag）→ 运行，这一步就是人工闸。加上 main 分支已配"需 PR 才能合并"，代码闸 + 部署闸齐全。将来升级 GitHub Team（$4/人/月）可改回 Required reviewers 模式。
- **Environment 在这套方案里的唯一实际作用**：给 OIDC 的 `sub` 提供 **`environment:<名字>`** 这一维，与 `07-获取应用iam密钥` 信任策略里的 `repo:ORG/REPO:environment:test|uat|main` **一一对应**；名字对不上（比如环境叫 `production` 而策略写 `main`）会直接 **AccessDenied**。这也正是"environment 名必须与分支名保持同名约定"的实际价值——少一套需要对齐的命名。

（可选加固：`main` 环境的 **Deployment branches and tags** 改成 Selected branches → 只允许 `main` 分支。这个选项 Free 计划可用。）

### ③ 提交邮箱验证（charles221900 个人账号，一次）

**怎么找**：右上角头像 → **Settings** → 左侧栏 **Emails**。直达 URL：`https://github.com/settings/emails`
**配置什么**：**Add email address** 填 `charles@shinypathway.com` → 去邮箱点验证链接。没验证的话提交只显示纯文本 charles、不挂头像。

## 二、日常使用的可视化页面

### 看流水线 / 审批 / 重跑

**怎么找**：仓库页 → 顶部 **Actions** 标签 → 左侧选 **CICD** workflow → 点某次 run。
- **看本次版本号**：build-push job 日志里的镜像 tag（`<env>-vN`，N=run 序号），回滚时要用；
- **审批 prod**：Free 私有仓库无环境审批，正常不会出现审批卡点（生产闸=手动 Run workflow，见 §一②）；将来升级 Team 开了 Required reviewers 后，run 页面会出现黄色 "Review deployments" → 点它 → 勾选 **`main`** 环境 → **Approve and deploy**；
- **重跑**：run 页面右上 **Re-run all jobs**（配置错误修好后用）；
- **看失败原因**：点红叉的 job → 展开红色步骤；deploy job 的日志里直接包含 EC2 端 deploy.sh 的完整输出（pull/up/冒烟/清理），不用另外上机器查。

### 回滚 / 手动指定环境部署

**怎么找**：Actions → CICD → 右侧 **Run workflow** 下拉（灰色按钮）。
**填什么**：Branch 选对应分支 → `environment` 选目标环境 → `image_tag` 填要回退到的不可变版本 tag（`<env>-vN`，如 `test-v12`，从 ECR 控制台或上次成功 run 的日志里查）→ **Run workflow**。填了 tag 会跳过构建直接部署旧镜像；prod 仍要过审批。
填了 `image_tag` 会跳过构建、直接把该版本部署上去；命令行兜底同样可用：`../09-远程执行与手动部署/deploy-env.sh <env> all <env>-vN`。

### 推送结果（AWS 侧）

ECR 仓库 Images 页签看新 tag：`https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1`（每环境独立仓库 `<env>/css-xxx`，`<env>-vN` 与浮动 `<env>` 双 tag 指向同一 digest；lifecycle 每仓库保留最近 5 个镜像）。

## 三、发布操作（命令行侧）

> 现阶段下表的 push 只触发**推镜像**（`<env>-vN`）；推完后手动 `bash docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh <env>` 完成部署。

| 目标 | 命令 |
|------|------|
| 发 test | `git push neworg test` |
| 发 uat | `git checkout uat && git merge test && git push neworg uat` |
| 发 prod | `git checkout main && git merge uat && git push neworg main` → 去 Actions 审批（恢复 deploy job 后） |
| 同步老仓库 | 先合到 `upstream-sync`（不触发部署），验证后再进 test——见 [../cicd-操作手册.md](../cicd-操作手册.md) |

## 四、workflow 文件本身（要改流水线时）

位置：两仓库各自的 `.github/workflows/cicd.yml`（Backend 还有 `deploy/aws/{build-push.sh,ssm-run.sh}`；Frontend 有 `.github/scripts/ssm-run.sh`）。job 结构：lint（仅检查本次改动的文件，与 pre-commit 语义一致）→（unit-test/typecheck 观察模式）→ build-push → migrate（仅 Backend，uat/prod 先快照）→ deploy。**migrate/deploy 自 2026-07-28 晚已启用**（早期版本曾注释掉，文档若见"已注释"字样均为过时描述）。改动走正常分支流程，**改 workflow 也要经 test 验证再晋级**。

## 五、常见失败对照

| 现象 | 原因/处理 |
|------|-----------|
| configure-aws-credentials 报 Not authorized | 分支不在角色信任策略里，或 **environment 名与信任策略对不上**（只信 `test`/`uat`/`main` 三个分支与**同名的**三个 Environment，见 `07-获取应用iam密钥`） |
| Parameter not found | 该环境的 `/css/<env>/*.env` 还没灌入 Parameter Store（`11-parameter-store`） |
| ECR push 报 not authorized/not exist | 目标环境的 `<env>/css-xxx` 仓库未建（`02-ecr`）或角色权限与前缀不符 |
| ssm-run 报没有 Online 实例 | 见 [../09-远程执行与手动部署/README.md](../09-远程执行与手动部署/README.md) |
| deploy 冒烟失败 | 看 job 日志里 deploy.sh 输出定位是哪个栈没起来 |
| prod 一直转圈 | 在等审批：run 页面 Review deployments |
