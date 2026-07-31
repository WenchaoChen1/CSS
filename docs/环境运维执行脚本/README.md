# docs/环境运维执行脚本（原 docs/新aws账号）—— 新账号（582797602427 / us-east-1）运维脚本目录

> 📋 **谁管什么先看 [职责划分.md](职责划分.md)**（Terraform vs 脚本 vs CI 的完整分工与快速索引）。
>
> ⚠️ **资源的创建/修改/删除已整体迁移到独立仓库 `css-terraform/`**（工作区同级，规范见其 CLAUDE.md；
> 组件用法与控制台入口见其 `使用说明/`）。本目录只保留**运维脚本**：数据库运维 / 镜像构建推送 /
> SSM 部署 / 参数上传 / 密钥发放 / 开发者 SSH。标签键 = `EnvironmentGroup` + `Environment`（成本分摊两键均已激活）。
>
> 本目录只作用于**新账号**；老账号（021213872872）数据迁移工具在 [`../老aws账号/`](../老aws账号/README.md)，勿混淆。
> 全部 bash（本机 git-bash 或 EC2 可跑）、幂等可重复执行。

## CI/CD 总流程（一次发布发生了什么）

```
你本机                      GitHub Actions（.github/workflows/cicd.yml）        AWS
git push test/uat ────────▶ lint（仅本次改动）→ 构建 7 镜像
                            → OIDC 换临时凭证（假扮 css-deploy-<env>，无长期 key）
                            → 推 ECR：<env>-vN（不可变版本号）+ <env>（浮动）──▶ <env>/css-xxx
                            →（uat：migrate 前自动 RDS 快照）
                            → SSM send-command ────────────────────────────▶ 标签 Environment=css-<env> 的 EC2
                                                                             解包 /opt/css-cicd → deploy.sh：
                                                                             渲染 env → pull → up → 冒烟 → prune
                            workflow 全绿 = 部署完成；任何一步红叉即停
git push main ────────────▶ 同上但【只构建不部署】；部署生产 = 手动 Run workflow（人工闸）
```

**职责分工**：GitHub Actions（→ [08](08-github-actions-cicd/README.md)）管"构建什么、什么时候发、发给谁"；
SSM + deploy.sh（→ [09](09-远程执行与手动部署/README.md)）管"命令安全送进私网机器 + 机器上跑起来并验证"。

| 分支 push | 环境 | 快照 | 审批 | 目标机（标签） |
|-----------|------|------|------|----------------|
| `test` | test | 无（数据可弃） | 无 | `Environment=css-test` |
| `uat` | uat | migrate 前自动 | 无 | `Environment=css-uat` |
| `main` | prod | migrate 前自动 + alembic 核对 | **只构建不部署；部署=手动 Run workflow**（GitHub Free 无环境审批的替代闸） | `Environment=css-prod` |
| `upstream-sync` | —（老仓库合并中转，不触发） | — | — | — |

回滚 = Actions → Run workflow → 选环境 + 填上一个不可变版本 tag `<env>-vN`（如 `test-v12`，从 ECR 或上次成功 run 日志查）；
或手动 `09/deploy-env.sh <env> all <env>-vN`。

## 目录一览（9 个文件夹 + 根目录文件）

| # | 文件夹 | 脚本 | 作用 |
|---|--------|------|------|
| 03 | [`03-本地构建推送镜像/`](03-本地构建推送镜像/README.md) | `build-images.sh`（只构建）、`push-ecr.sh`（构建+推送） | Windows 本机镜像工具（CI 的兜底：应急/首次灌仓/调试） |
| 05 | [`05-数据库运维/`](05-数据库运维/README.md) | `create-databases.sh`、`sync-db.sh`、`restore-dump-via-gw.sh`、`anonymize-db.sh`、`create-db-accounts.sh`、`change-db-password.sh`、`reown-db-objects.sh` | 库内一切（Terraform 管不到）：建库/同步/恢复/脱敏/账号/改密/对象 owner。⚠️ 每次 restore/sync 后必须重跑 reown |
| 06 | [`06-服务器密钥与访问/`](06-服务器密钥与访问/README.md) | `create-instance-keys.sh`、`setup-ssh-key.sh`、`grant-dev-ssh.sh`、`revoke-dev-ssh.sh`、`toggle-termination-protection.sh` | 一机一钥管理、开发者临时 SSH 钥（带过期时间）、TF 重建实例前解终止保护 |
| 07 | [`07-获取应用iam密钥/`](07-获取应用iam密钥/README.md) | `issue-app-s3-key.sh <env> [--new-key]` | 发/查 `css-app-<env>` 用户的 access key（key 按红线永不进 Terraform） |
| 08 | [`08-github-actions-cicd/`](08-github-actions-cicd/README.md) | `setup-github-actions.sh` | GitHub Actions 配置与使用手册（Variables/Environments 一键配置） |
| 09 | [`09-远程执行与手动部署/`](09-远程执行与手动部署/README.md) | `setup-ssm.sh`、`run.sh <env> '<命令>'`、`deploy-env.sh <env> [stack] [tag]` | SSM 命令通道：远程执行、手动部署/回滚（CI 之外的兜底入口） |
| 10 | [`10-服务自愈与开机自启/`](10-服务自愈与开机自启/README.md) | `setup-autodeploy.sh <env>` | 已部署服务的开机自启 + 冒烟自愈（**非发版工具**）。**⏸ 暂不使用**：安装需负责人确认（脚本内置 CONFIRM 闸）；TF 重建机器后会丢，需重装 |
| 11 | [`11-parameter-store/`](11-parameter-store/README.md) | `put-params.sh <env>` | 把工作区根 `deploy-env/<env>/` 底稿灌入 `/css/<env>/*`（运行时配置唯一事实源；test ✅ 已灌，uat/prod 首次部署前灌/校准） |
| 12 | [`12-成本账单/`](12-成本账单/README.md) | `activate-cost-tags.sh` | 成本分摊标签激活（✅ 07-31 两键已激活，幂等）；账单侧脚本归口 |
| — | 根目录 | [`职责划分.md`](职责划分.md) | 本目录脚本管什么/不管什么 + 部署分工 + 快速索引（Terraform 侧职责见 css-terraform CLAUDE.md §一） |

**已删除的编号目录**（01-vpc / 02-ecr / 04-rds / 12-alb / 13-s3 / 14-cloudwatch / 15 等）：这些"创建类"
组件已全部由 css-terraform 接管，说明在其 `使用说明/` 对应文档；`tag-all-resources.sh` 已随标签切换退役。
（2026-07-31 重命名：`03-推送镜像`→`03-本地构建推送镜像`、`05-数据同步`→`05-数据库运维`、`06-ec2`→`06-服务器密钥与访问`、
`07-iam`→`07-获取应用iam密钥`（脚本 `create-app-s3-user.sh`→`issue-app-s3-key.sh`）、`08-github-actions推镜像`→`08-github-actions-cicd`、`09-ssm-run-command`→`09-远程执行与手动部署`、`10-自动重新部署`→`10-服务自愈与开机自启`。）

## 约定（仍然有效的部分）

- **命名规范**：组级共享资源带组前缀 `css-non-prod-*` / `css-prod-*`（连字符，不用 `nonprod` 连写）；
  环境专属资源用环境名（应用机 `css-<env>-app`、ALB `css-<env>`、S3 `css-<env>-<账号>`、
  IAM `css-deploy/ec2/app-<env>`、ECR `<env>/css-xxx`、参数 `/css/<env>/*`、库名 `css-<env>-main`/`-ocr`）。
  堡垒机 2026-07-30 已统一为 `css-non-prod-bastion` / `css-prod-bastion`。
  ⚠️ SG GroupName/IAM 角色名/运行中实例 KeyName **创建后不可改**——改名=新建+迁移+删旧（现统一走 css-terraform）。
- **标签规范**：`EnvironmentGroup`（组）+ `Environment`（环境；共享资源=**`css-shared`**）+ `ManagedBy=terraform`。
  ⚠️ `Environment` 是**控制面标签**：IAM `ssm:SendCommand` 条件与 09 的部署脚本按它定位目标机——
  共享资源（堡垒机等）打成 `css-test` 会被 test 的部署命令选中，**往错误机器上发部署**。
- **镜像 tag**：CI 推 `<env>-vN`（回滚依据）+ 浮动 `<env>`；手动推 `<env>-manual-<sha7>`；每仓库 lifecycle 保留 5 个。
- **网络三铁律**：① SSH 只经堡垒机（仅白名单 IP）；② 系统 Web 只经本环境 ALB（kafka-ui 只走开发入口 ALB
  `css-non-prod-entry`，白名单）；③ RDS 只能内网访问。
- **非生产数据必须脱敏**：从 preprod/生产导入真实数据后跑 `05-数据库运维/anonymize-db.sh <test|uat>`
  （email 前缀 `1`、phone 后缀 `1`、口令统一测试值）；`prod` 参数会被脚本直接拒绝。
