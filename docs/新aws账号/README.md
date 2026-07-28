# docs/新aws账号 —— 新账号（582797602427 / us-east-1）资源创建与运维脚本

> 本目录只作用于**新账号**；老账号（021213872872）数据迁移工具在同级 **[`../老aws账号/`](../老aws账号/README.md)**，勿混淆。
> 按维度一个文件夹；全部 bash（本机 git-bash 或 EC2 可跑）、幂等可重复执行。
> **本目录覆盖并取代**：`部署包/bin/打镜像推ECR.ps1`、`部署包/bin/创建ECR仓库.ps1`（已删除）。
> 说明文档：[`../aws账号脚本说明.md`](../aws账号脚本说明.md)；设计文档：`docs/环境/`（拓扑/群组/成本）与 `docs/生产部署/03-CICD-GitHub-Actions.md`（CI/CD v2.2）。
> ⚠️ 标注 💰 的脚本创建计费资源；现 FREE plan（剩 $53.87 credits）下小规格已可建（RDS css-non-prod、网关机均已建成），`css-prod` 实例仍被拦截，等升级 Paid plan。

## CI/CD 总流程（一次发布发生了什么）

```
你本机                         GitHub（托管 runner）                    AWS
git push neworg test ───────▶ ① CICD workflow 触发（.github/workflows/cicd.yml）
                               │  lint（后端只查本次改动的 py；前端 eslint）
                               │  构建 Docker 镜像
                               │  OIDC 换临时凭证（无长期 AK/SK）──────▶ 假设 css-deploy-test 角色
                               │  推送 ECR：test-vN（不可变版本号，N=run 序号自增）+ test（浮动）──▶ test/css-xxx（每环境独立仓库）
                               │  （uat/prod：先自动 RDS 快照；prod：停等人工审批）
                               ▼
              ⚠️ 现状：CI 到此为止（**只推镜像**，migrate/deploy job 已在 workflow 注释）；
              部署 = 手动执行 `09-ssm-run-command/deploy-env.sh <env>`。以下 ②-④ 是恢复注释后的自动部署目标态：
                              ② run.sh 经 SSM send-command ──────────▶ 标签 CssEnv=css-test 的 EC2
                                                                    ③ 解包 /opt/css-cicd/ → deploy.sh：
                                                                       渲染 env → pull → up → 冒烟 → prune
                              ④ workflow 全绿 = 部署完成；任何一步失败红叉即停
```

**职责分工**：GitHub Actions（→ [08](08-github-actions推镜像/README.md)）管"构建什么、什么时候发、发给谁"；SSM + deploy.sh（→ [09](09-ssm-run-command/README.md)）管"命令安全送进私网机器 + 机器上跑起来并验证"。

| 分支 push | 环境 | 快照 | 审批 | 目标机（标签） |
|-----------|------|------|------|----------------|
| `test` | test | 无（数据可弃） | 无 | `CssEnv=css-test` |
| `uat` | uat | migrate 前自动 | 无 | `CssEnv=css-uat` |
| `main` | prod | migrate 前自动 + alembic 核对 | **只构建不部署；部署生产=手动 Run workflow**（GitHub Free 无环境审批，此为替代闸） | `CssEnv=css-prod` |
| `upstream-sync` | —（老仓库合并中转，不触发部署） | — | — | — |

回滚 = Actions → Run workflow → 选环境 + 填上一个不可变版本 tag `<env>-vN`（如 `test-v12`，从 ECR 或上次成功 run 日志查）；现阶段 deploy job 注释中，回滚同样走手动 `deploy-env.sh <env> all <env>-vN`。**首次启用检查单**：① GitHub 侧零配置（prod 闸=手动触发模式，见 [08 §一②](08-github-actions推镜像/README.md)；误建的 `main` 环境请删）→ ② test 机 SSM 就绪（✅）→ ③ `/css/test/*` 参数（✅）→ ④ 先跑 Backend workflow 再 Frontend → ⑤ 全绿后晋级 uat/main。

## 目录与执行顺序

| # | 文件夹 | 脚本 | 作用 | 费用 | 状态 |
|---|--------|------|------|------|------|
| 1 | `01-vpc/` | `create-vpc.sh <nonprod\|prod>` | 两套 VPC 全套网络（子网×4/IGW/路由/S3端点/安全组，带 Group 标签） | 免费 | ✅ 两组已执行（2026-07-28） |
| 2 | `02-ecr/` | `create-ecr.sh [env|all]` | **每环境独立** ECR 仓库（`<env>/css-xxx`，3×7=21 个）+ scanOnPush + 保留 5 | 免费 | ✅ 已重建（2026-07-28 全量删除重建） |
| 3 | `03-推送镜像/` | `push-ecr.sh <test\|uat\|prod> [tag]` | 手动构建 7 镜像并双 tag 推送（缺省 `<env>-manual-<sha7>` + `<env>` 浮动；CI 版本号为 `<env>-vN`） | 按存储 | 随用随跑 |
| 4 | `04-rds/` | `create-rds.sh <nonprod\|prod>` 💰 | 非生产 `css-non-prod`（t4g.micro）/ 生产 `css-prod`（t4g.medium Multi-AZ+删除保护），私有子网、Secrets Manager 托管密码 | ~$15 / ~$120 月 | 非生产 ✅ 已建（2026-07-28，新 VPC）；css-prod 等 Paid plan |
| 5 | `05-数据同步/` | `create-databases.sh <host> <pw> <env...>`；`sync-db.sh <源DSN> <目标DSN>`；`restore-dump-via-gw.sh <env> <main.dump> <ocr.dump>` | 建库（**库名 `css-<env>-main` / `css-<env>-ocr`**，ocr 带 pgvector）；库到库同步；本地 dump 经 S3+SSM 网关机恢复进私网 RDS | 免费 | test 库 ✅ 已从 preprod 备份载入 |
| 6 | `06-ec2/` | `create-app-ec2.sh <env> [type]` 💰；`create-gateway.sh <nonprod\|prod>` 💰 | 应用机（私网固定 IP：test 10.20.10.10 / uat 10.20.11.10 / prod 10.10.10.10）；非生产三合一网关机（堡垒+NAT+反代，**反代是过渡通道，ALB 就绪后收掉**）/ 生产堡垒机+NAT 网关 | ~$60-140/台 | 网关机 css-nonprod-gw ✅ 已建（EIP 3.225.148.166）；应用机等 Paid plan（旧 test 机已删，现无应用机） |
| 7 | `07-iam/` | `create-iam.sh` | GitHub OIDC + 三环境隔离角色（css-deploy-\*/css-ec2-\*/css-app-\*，key 不跨环境） | 免费 | ✅ 已执行 |
| 8 | `08-github-actions推镜像/` | `setup-github-actions.sh <backend\|frontend\|all>` | 一键配置两仓库的 Variables/Environments/prod 审批人（需 gh CLI；workflow 本体已在仓库） | 免费 | ⏳ 待执行 |
| 9 | `09-ssm-run-command/` | `setup-ssm.sh <env> <instance-id>`；`run.sh <env> '<命令>'`；`deploy-env.sh <env> [stack] [tag]` | 把 EC2 配成 SSM 部署目标；远程执行命令；**手动部署（现阶段发布入口）** | 免费 | ⏳ 应用机建后执行（旧 test 机已删；网关机已在 SSM 在管） |
| 10 | `10-自动重新部署/` | `setup-autodeploy.sh <env>` | systemd 开机自动拉起三栈 + 5 分钟冒烟自愈（经 SSM 安装，不是发布入口） | 免费 | ⏳ 等首次部署后执行 |
| 11 | `11-parameter-store/` | `put-params.sh <env>` | 把工作区根 deploy-env/<env>/ 底稿灌入 `/css/<env>/*`（SecureString，唯一事实源） | 免费 | test ✅ 已灌 |
| 12 | `12-alb/` | `create-alb.sh <nonprod\|prod>` 💰 | **系统 Web 唯一入口** ALB（域名访问；就绪后收掉网关机反代过渡通道） | ~$16/月+LCU | ⏳ 等应用机+域名 |

## 完整建环境顺序（新 VPC 从零到可用）

```
01-vpc ✅ → 07-iam ✅ → 02-ecr ✅ → 08-github-actions(仓库配置)
→ 04-rds(非生产 css-non-prod ✅；css-prod 等 Paid plan) → 06-ec2(gateway ✅ css-nonprod-gw)
→ 05-数据同步(建库+载入：test ✅ 已从 preprod 备份载入) → 11-parameter-store(test ✅ 已灌)
→ [升级 Paid plan] → 06-ec2(app) → 09-ssm(新机验证) → 12-alb(等应用机+域名)
→ push 代码触发 CI 推镜像 → 手动 09/deploy-env.sh <env> 部署 → 10-自动重新部署(自愈)
```

## 约定

- **标签**：所有资源 `Group=css-non-prod|css-prod`；应用机另有 `CssEnv=css-test|css-uat|css-prod`（SSM 部署按此定位）。
- **库名**（2026-07-28 拍板）：`css-test-main`/`css-test-ocr`/`css-uat-main`/`css-uat-ocr`/`css-prod-main`/`css-prod-ocr`——test 已按新库名载入 `css-non-prod`；旧库名 `css_<env>`/`ocr_<env>` 切换时 env 里的 `POSTGRES_DB`、`OCR_*_URL` 须同步改。
- **镜像 tag 规范**（2026-07-28 拍板）：CI 推不可变版本号 `<env>-vN`（N=GitHub Actions run 序号自增，如 `test-v12`，回滚依据）+ 浮动 `<env>` tag；手动推送用 `<env>-manual-<sha7>`；每仓库 lifecycle 只保留最近 5 个镜像。
- **凭证隔离**：三环境 AWS key/角色互不复用（03-CICD §4.5）；S3 用户 key 在填 Parameter Store 时生成。
- **网络访问规范**（2026-07-28 拍板，详见 [`12-alb/`](12-alb/README.md)）：
  1. 所有 EC2 的 **SSH 只能经堡垒机**（nonprod=css-nonprod-gw EIP 3.225.148.166、prod=css-prod-bastion，仅放行管理 IP 221.214.0.190/32）；
  2. 系统 **Web 访问只能通过 ALB 配置的域名**（nonprod 已建 css-nonprod-alb-sg=sg-0c8f420e1e46b5b4b，ALB 等应用机+域名后由 `12-alb/create-alb.sh` 创建；网关机 nginx 80/8080 反代是过渡通道，ALB 就绪后收掉）；
  3. **RDS 只能内网访问**（`--no-publicly-accessible`，安全组仅放行 app/网关 SG）。
