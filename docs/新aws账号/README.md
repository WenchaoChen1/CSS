# docs/新aws账号 —— 新账号（582797602427 / us-east-1）资源创建与运维脚本

> ⚠️ **2026-07-30 重大变更**：资源的创建/修改/删除已整体迁移到独立仓库 **css-terraform**（工作区同级，规范见其 CLAUDE.md）；本目录的创建类脚本已删除，仅保留【数据同步 / 推镜像 / SSM 部署 / 参数上传 / 密钥发放】等运维脚本。标签键已切换为 EnvironmentGroup/Environment（原 Group/CssEnv）。下文的脚本编号表格保留作历史与运维参考。

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
| 1 | `01-vpc/` | `create-vpc.sh <nonprod\|prod>`；`rename-security-groups.sh <plan\|apply\|verify\|canary\|cutover\|cleanup>` | 两套 VPC 全套网络（子网×4/IGW/路由/S3端点/安全组，带双标签）；**安全组改名迁移**（GroupName 不可改，用"新建+双挂+金丝雀+切换+删旧"零中断把 `css-nonprod-*` 换成 `css-non-prod-*`） | 免费 | ✅ 两组已执行（2026-07-28）；✅ 非生产 4 个安全组已改名（2026-07-29，旧组已删） |
| 2 | `02-ecr/` | `create-ecr.sh [env|all]` | **每环境独立** ECR 仓库（`<env>/css-xxx`，3×7=21 个）+ scanOnPush + 保留 5 | 免费 | ✅ 已重建（2026-07-28 全量删除重建） |
| 3 | `03-推送镜像/` | `push-ecr.sh <test\|uat\|prod> [tag]` | 手动构建 7 镜像并双 tag 推送（缺省 `<env>-manual-<sha7>` + `<env>` 浮动；CI 版本号为 `<env>-vN`） | 按存储 | 随用随跑 |
| 4 | `04-rds/` | `create-rds.sh <nonprod\|prod>` 💰 | 非生产 `css-non-prod`（t4g.micro）/ 生产 `css-prod`（t4g.medium Multi-AZ+删除保护），私有子网、Secrets Manager 托管密码 | ~$15 / ~$120 月 | 非生产 ✅ 已建（2026-07-28，新 VPC）；css-prod 等 Paid plan |
| 5 | `05-数据同步/` | `create-databases.sh <host> <pw> <env...>`；`sync-db.sh <源DSN> <目标DSN>`；`restore-dump-via-gw.sh <env> <main.dump> <ocr.dump>`；**`anonymize-db.sh <test\|uat> [口令]`** | 建库（**库名 `css-<env>-main` / `css-<env>-ocr`**，ocr 带 pgvector）；库到库同步；本地 dump 经 S3+SSM 网关机恢复进私网 RDS；**非生产脱敏**（email 加前缀 1 / phone 加后缀 1 / password_hash 统一为 `Test1234!`，prod 拒绝执行） | 免费 | test 库 ✅ 已从 preprod 备份载入；✅ 2026-07-29 已脱敏 |
| 6 | `06-ec2/` | `setup-ssh-key.sh [公钥] [实例…]`；`create-instance-keys.sh`；`create-app-ec2.sh <env> [type] [keypair]` 💰；`create-gateway.sh <nonprod\|prod>` 💰；`delete-ec2.sh <目标> yes` | SSH 公钥导入为 key pair（并可经 SSM 补装到已有机器）；**一机一钥**（每台机器一把专属 ed25519）；应用机（私网固定 IP：test 10.20.10.10 / uat 10.20.11.10 / prod 10.10.10.10，默认 m7i-flex.large）；非生产网关机（**堡垒 + NAT 两件事**，nginx 反代过渡通道已于 2026-07-29 收掉，脚本不再安装）/ 生产堡垒机+NAT 网关；删实例并释放 EIP | ~$69/台（m7i-flex.large） | ✅ 网关机 css-non-prod-gw（EIP 3.225.148.166）、css-test-app、css-uat-app 均已建；专属 key pair `css-non-prod-gw`/`css-test`/`css-uat`，个人公钥 `wenchao` 作第二通道；prod 应用机 ⏳ |
| 7 | `07-iam/` | `create-iam.sh` | GitHub OIDC + 三环境隔离角色（css-deploy-\*/css-ec2-\*/css-app-\*，key 不跨环境） | 免费 | ✅ 已执行 |
| 8 | `08-github-actions推镜像/` | `setup-github-actions.sh <backend\|frontend\|all>` | 一键配置两仓库的 Variables/Environments/prod 审批人（需 gh CLI；workflow 本体已在仓库） | 免费 | ⏳ 待执行 |
| 9 | `09-ssm-run-command/` | `setup-ssm.sh <env> <instance-id>`；`run.sh <env> '<命令>'`；`deploy-env.sh <env> [stack] [tag]` | 把 EC2 配成 SSM 部署目标；远程执行命令；**手动部署（现阶段发布入口）** | 免费 | ⏳ 应用机建后执行（旧 test 机已删；网关机已在 SSM 在管） |
| 10 | `10-自动重新部署/` | `setup-autodeploy.sh <env>` | systemd 开机自动拉起三栈 + 5 分钟冒烟自愈（经 SSM 安装，不是发布入口） | 免费 | ⏳ 等首次部署后执行 |
| 11 | `11-parameter-store/` | `put-params.sh <env>` | 把工作区根 deploy-env/<env>/ 底稿灌入 `/css/<env>/*`（SecureString，唯一事实源） | 免费 | test ✅ 已灌 |
| 12 | `12-alb/` | `create-alb.sh <test\|uat\|prod> [域名]` 💰；`revoke-gw-proxy.sh <nonprod\|prod>`；`revoke-kafkaui-public.sh <test\|uat\|prod>` | **系统 Web 唯一入口** ALB——**每环境一个，名字就是环境名**（`css-test`/`css-uat`/`css-prod`），前端 :80/:443、WebSocket idle 3600s、双标签；kafka-ui 默认不挂 ALB，走堡垒机隧道。`revoke-gw-proxy.sh` 收掉网关机的 80/8080 过渡通道；`revoke-kafkaui-public.sh` 回收 kafka-ui 公网暴露 | ~$20/月/个含 LCU | ✅ `css-test`（`css-test-524317374.us-east-1.elb.amazonaws.com`，目标 10.20.10.10 healthy，前端实测 200）、`css-uat`（`css-uat-1366981991.us-east-1.elb.amazonaws.com`，目标 10.20.11.10，uat 未部署故暂 unhealthy）均已建；旧共享 `css-nonprod-alb` 已删除；`css-prod` ⏳ 等 prod 应用机 |
| 13 | `13-s3/` | `create-s3.sh [env\|all]` | 各环境应用存储桶（后端 `S3_STORAGE_BUCKET_NAME`），一环境一个：阻断公共访问 + SSE-S3 + 版本控制 + 生命周期 + 双标签 + 最小 CORS | 极小（~$2/月） | ✅ test=`css-test-582797602427`（旧桶 102 对象已迁入、env 已更新灌参数）、uat=`css-uat-582797602427`、prod=`css-prod-582797602427`（纯名 `css-test`/`css-prod` 被别的账号占用，回退带账号后缀）→ [13-s3/README.md](13-s3/README.md) |
| — | **根目录** | `tag-all-resources.sh [--dry-run]` | 给**已存在**资源批量补打 `Group` + `CssEnv` 双标签（不在编号文件夹里，因为它横跨所有维度）；幂等，可先 `--dry-run` 看清单 | 免费 | ✅ 2026-07-29 已执行 |

## 完整建环境顺序（新 VPC 从零到可用）

```
01-vpc ✅ → 07-iam ✅ → 02-ecr ✅ → 13-s3 ✅ → 08-github-actions(仓库配置)
→ 04-rds(非生产 css-non-prod ✅；css-prod 等 Paid plan) → 06-ec2(gateway ✅ css-non-prod-gw)
→ 05-数据同步(建库+载入：test ✅ 已从 preprod 备份载入 → anonymize-db.sh 脱敏 ✅)
→ 11-parameter-store(test ✅ 已灌) → 06-ec2(app ✅ test/uat) → 09-ssm(新机验证)
→ push 代码触发 CI 推镜像 → 手动 09/deploy-env.sh <env> 部署
→ 12-alb(每环境一个：css-test ✅ / css-uat ✅ / css-prod ⏳) → 12-alb/revoke-gw-proxy.sh(收过渡通道 ✅)
→ 10-自动重新部署(自愈) → tag-all-resources.sh(补标签，任何时候可重跑 ✅)
```

## 约定

- **命名规范**（2026-07-29 拍板并已全量落地）：**资源名一律带连字符**——非生产 `css-non-prod-*`、生产 `css-prod-*`，
  与 VPC 名（`css-non-prod` / `css-prod`）、RDS 实例名、`Group` 标签值逐字一致；**不再出现 `nonprod` 这种连写形式**。
  - 已落地对象：VPC / 子网 / 路由表 / IGW / S3 端点、安全组 `css-non-prod-{gw,alb,app,rds}-sg`、
    网关机 `css-non-prod-gw`（含其 EIP `css-non-prod-gw-eip`）、网关机 IAM 角色 `css-gw-non-prod`、RDS `css-non-prod`。
  - 例外（**故意**不带组前缀）：**环境专属**资源用环境名——应用机 `css-<env>-app`、ALB `css-<env>`、
    目标组 `css-<env>-fe-tg`、S3 桶 `css-<env>-<账号>`、IAM `css-deploy-<env>`/`css-ec2-<env>`/`css-app-<env>`、
    ECR `<env>/css-xxx`、参数 `/css/<env>/*`、库名 `css-<env>-main`/`-ocr`。
  - ⚠️ **改名不是改个字段就完事**：AWS 的**安全组 `GroupName`/`Description`、IAM 角色名、运行中实例的 `KeyName`
    创建后都不可修改**，只能"新建 → 迁移引用 → 删旧"（安全组见 `01-vpc/rename-security-groups.sh`，
    IAM 角色见 `06-ec2/create-gateway.sh` 内置的自动换绑）。**只有 `Name` 标签能随便改。**
- **标签规范**（2026-07-29 拍板并已全量落地）：**每个资源都带两个标签**——
  - `Group` = `css-non-prod` | `css-prod`（成本/权限分组）；
  - `CssEnv` = `css-test` | `css-uat` | `css-prod`（**环境专属**资源，如应用机、各环境 ALB/目标组、S3 应用桶）；
  - `CssEnv` = **`css-shared`**（**跨环境共享**资源：VPC、子网、路由表、IGW、S3 端点、安全组、网关机/堡垒机及其 EIP、非生产 RDS 实例与子网组、`css-dbsync` 中转桶）。
  - ⚠️ **共享资源为什么必须打 `css-shared` 而不能打 `css-test`**：IAM 的 `ssm:SendCommand` 条件、`09-ssm-run-command/run.sh`
    与 `deploy-env.sh` 都按 `CssEnv=css-<env>` **定位部署目标机**。给网关机（或 VPC/安全组）打 `css-test`，
    它就会被 test 的部署命令选中 → **往错误的机器上发部署**。`css-shared` 既满足"人人两标签"，又不会被任何环境的部署逻辑命中。
  - 存量补打：根目录 `tag-all-resources.sh`（幂等，`--dry-run` 预览）；新建资源无需补打——
    `01-vpc` / `04-rds` / `06-ec2`(gateway) / `12-alb` / `13-s3` 的创建脚本都已内置双标签。
- **库名**（2026-07-28 拍板）：`css-test-main`/`css-test-ocr`/`css-uat-main`/`css-uat-ocr`/`css-prod-main`/`css-prod-ocr`——test 已按新库名载入 `css-non-prod`；旧库名 `css_<env>`/`ocr_<env>` 切换时 env 里的 `POSTGRES_DB`、`OCR_*_URL` 须同步改。
- **镜像 tag 规范**（2026-07-28 拍板）：CI 推不可变版本号 `<env>-vN`（N=GitHub Actions run 序号自增，如 `test-v12`，回滚依据）+ 浮动 `<env>` tag；手动推送用 `<env>-manual-<sha7>`；每仓库 lifecycle 只保留最近 5 个镜像。
- **凭证隔离**：三环境 AWS key/角色互不复用（03-CICD §4.5）；S3 用户 key 在填 Parameter Store 时生成。
- **网络访问规范**（2026-07-28 拍板，2026-07-29 收口完成，详见 [`12-alb/`](12-alb/README.md)）：
  1. 所有 EC2 的 **SSH 只能经堡垒机**（nonprod=css-non-prod-gw EIP 3.225.148.166、prod=css-prod-bastion，仅放行管理 IP 221.214.0.190/32）；
  2. 系统 **Web 访问只能通过 ALB**（每环境一个：`css-test` / `css-uat` / `css-prod`；nonprod ALB 安全组 `css-non-prod-alb-sg`=`sg-0c7b0b571d74b1f2f`）。
     **网关机 nginx 80/8080 过渡通道已于 2026-07-29 撤销**（`12-alb/revoke-gw-proxy.sh`）：gw-sg 的 80/8080 入站、
     app-sg 的"来自网关的 80"都已删，网关机 nginx 已停用并禁用，`01-vpc/create-vpc.sh` 也不再放行这两个口；
  3. **RDS 只能内网访问**（`--no-publicly-accessible`，安全组仅放行 app/网关 SG）。
- **网关机现在只剩两条入站**：`22 ← 221.214.0.190/32`（SSH 跳板）+ `10.20.0.0/16 全协议`。
  后者**是 NAT 回程，不是给 SSH 的**——私有子网的 test/uat 没有公网 IP，出网全靠网关机转发，回程流量必须放行；
  删了它两台机器立刻断网（拉不了镜像、连不上 SSM）。应用机 SG 只有 `22 ← 网关机 SG` 和 `80 ← ALB SG`。
- **非生产数据必须脱敏**：从 preprod/生产导入真实数据后跑一次 `05-数据同步/anonymize-db.sh <test|uat>`
  （email 前缀 `1`、phone 后缀 `1`、password_hash 统一为 `Test1234!`）；`prod` 参数会被脚本直接拒绝。test ✅ 已执行。
