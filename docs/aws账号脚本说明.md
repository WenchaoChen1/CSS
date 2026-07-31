# AWS 账号脚本说明（新老账号两个文件夹的区分与使用指南）

> 脚本实体在同级两个文件夹：[`新aws账号/`](新aws账号/README.md)（我方资源创建与运维）与 [`老aws账号/`](老aws账号/README.md)（客户老账号数据迁移）。本文是索引与使用说明。2026-07-28。

## 一、新老账号，一眼分清

| | 老账号（客户遗留） | 新账号（我方环境） |
|---|---|---|
| AWS 账号 | `021213872872` / eu-central-1 | `582797602427` / us-east-1 |
| 用途 | 原团队 dev/preprod/staging（**数据迁移的只读来源**） | test / uat / prod 全部新环境 |
| 对应脚本 | **仅 `docs/老aws账号/`** | `docs/新aws账号/01~12` 全部 |
| 凭证 | `源环境.env` 的 `SRC_AWS_PROFILE`（勿提交） | 本机 default profile / OIDC / 实例角色 |

**规则**：老账号只拉不写；新账号脚本绝不碰老账号资源；两边凭证不混用。

## 二、老账号脚本（docs/老aws账号/，PowerShell）

| 脚本 | 作用 |
|------|------|
| `拉取数据库.ps1` | SSH 到老环境服务器 `docker exec pg_dump -Fc` 拉库到本地 `备份/`（支持 `-AllDatabases`） |
| `拉取docker-env.ps1` | 采集各容器环境变量 + 磁盘 .env 清单（迁移配置时对照用） |
| `拉取S3.ps1` | `aws s3 sync` 下载老账号桶，可 `-SizeOnly` 预估、`-PushToDst` 回推新桶 |
| `源环境.env(.example)` | 老环境 SSH 主机/密钥 + 新老两侧 AWS profile 配置（真实文件已 gitignore） |

## 三、新账号脚本（01~13 + 根目录 tag-all-resources.sh，bash，幂等）

执行顺序（简化版，完整版见 [新aws账号/README.md](新aws账号/README.md)）：`01-vpc → 07-应用s3密钥 → 02-ecr → 08-github-actions` → **升级 Paid plan** → `04-rds → 06-服务器密钥与访问 → 09-ssm验证 → 05-数据库运维` → CI 首次部署 → `10-自动重新部署`；03-本地构建推送镜像为 CI 备用手动工具；`11-parameter-store` 在填/改环境配置时随用。

| 文件夹 | 脚本 | 一句话 | 费用 |
|--------|------|--------|------|
| `01-vpc/` | `create-vpc.sh <nonprod\|prod>` | 两套 VPC 全套网络+安全组（10.20/10.10 网段，`Group`+`CssEnv=css-shared` 双标签，管理白名单 221.214.0.190/32；2026-07-29 起网关 SG 不再放行 80/8080） | 免费 ✅ |
| `02-ecr/` | `create-ecr.sh [env|all]` | **每环境独立** 3×7=21 个镜像仓库（`<env>/css-xxx`）+ 推送扫描 + 保留 5 | 免费 ✅ |
| `03-本地构建推送镜像/` | `push-ecr.sh <env> [tag]` | 手动构建 7 镜像双 tag 推送（缺省 `<env>-manual-<sha7>` + `<env>` 浮动；CI 版本号为 `<env>-vN`） | 存储费 |
| `04-rds/` | `create-rds.sh <nonprod\|prod>` | 非生产 `css-non-prod`（t4g.micro，✅ 已建于新 VPC）/ 生产 `css-prod`（t4g.medium Multi-AZ，等 Paid plan），私有子网 | 💰 |
| `05-数据库运维/` | `create-databases.sh` / `sync-db.sh` / `restore-dump-via-gw.sh` / **`anonymize-db.sh <test\|uat>`** | 按新库名规范建库（`css-<env>-main`/`css-<env>-ocr`，ocr 带 pgvector）；pg_dump→pg_restore 同步数据（VPC 内执行）；本地 dump 经 S3+SSM 网关机恢复进私网 RDS；**非生产脱敏**（email 前缀 1 / phone 后缀 1 / 口令统一 `Test1234!`，prod 拒绝执行；test ✅ 已跑） | 免费 |
| `06-服务器密钥与访问/` | `create-app-ec2.sh <env>` / `create-instance-keys.sh` / `create-gateway.sh <nonprod\|prod>` | 应用机（私网固定 IP）；一机一钥（每台专属 ed25519）；非生产网关机（**堡垒 + NAT**，反代已于 2026-07-29 收掉）/ 生产堡垒机+NAT 网关 | 💰 |
| `07-应用s3密钥/` | `create-iam.sh` | GitHub OIDC + 三环境隔离角色与 S3 用户（key 不跨环境） | 免费 ✅ |
| `08-github-actions-cicd/` | `setup-github-actions.sh` | 一键配置两仓库 GitHub Actions（Variables/Environments/审批人，需 gh CLI） | 免费 |
| `09-ssm-run-command/` | `setup-ssm.sh` / `run.sh` | 把 EC2 配成 SSM 部署目标；远程执行命令 | 免费 |
| `10-自动重新部署/` | `setup-autodeploy.sh <env>` | systemd 开机自启三栈 + 冒烟自愈 cron（经 SSM 安装） | 免费 |
| `11-parameter-store/` | `put-params.sh <env>` | 把 `deploy-env/<env>/` 底稿灌入 `/css/<env>/*`（SecureString，运行时唯一事实源） | 免费 |
| `12-alb/` | `create-alb.sh <test\|uat\|prod>` / `revoke-gw-proxy.sh <nonprod\|prod>` | **系统 Web 唯一入口** ALB——**每环境一个，名字=环境名**（`css-test` ✅ / `css-uat` ✅ / `css-prod` ⏳），双标签；`revoke-gw-proxy.sh` 收掉网关机 80/8080 过渡通道（✅ 已执行） | 💰 |
| `13-s3/` | `create-s3.sh [env\|all]` | 各环境应用存储桶（test=`css-test-582797602427`、uat=`css-uat`、prod=`css-prod-582797602427`），阻断公共访问+加密+版本控制+生命周期+双标签 | 极小 ✅ |
| **根目录** | `tag-all-resources.sh [--dry-run]` | 给已存在资源批量补 `Group`+`CssEnv` 双标签（共享资源用 `css-shared`，否则会被该环境的 SSM 部署命令误选中） | 免费 ✅ |

## 四、已被本脚本集取代（勿再使用）

- ~~`部署包/bin/打镜像推ECR.ps1`~~、~~`部署包/bin/创建ECR仓库.ps1`~~ → `03-本地构建推送镜像` / `02-ecr`（已删除）
- ~~`发布包/`（后更名 开发环境-连接服务器与部署脚本/）三个脚本~~ → 被 `03-本地构建推送镜像` 与 CI/CD 覆盖（已删除，故障表并入 `CSS_backend-main/deploy/README.md` §五）
- ~~`部署包/compose/{infra,backend,frontend}.yml`、`部署包/bin/{deploy.sh,同步部署文件到EC2.ps1}`、`部署包/env/{uat,prod}/*.example`~~ → 2026-07-28 瘦身删除，权威版本在 Backend 仓库 `deploy/`（CI 自动上传 EC2 `/opt/css-cicd/`）
- ~~`部署包/迁移/`~~ → 移入 `docs/老aws账号/`

**`部署包/` 已于 2026-07-28 整体退役**：剩余内容（本地 dev 的 compose/dev.yml + env/dev、env/test 真实配置底稿、本地dev/连接EC2 两个 ps1、换新版本核对清单）全部并入 Backend 仓库 `deploy/`。最终分工：**AWS 资源创建/推镜像归 docs/新aws账号，数据迁移归 docs/老aws账号，本地 dev 与 AWS 部署运行全归 Backend 仓库 `deploy/`（CI/CD）**。
