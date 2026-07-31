# AWS 群组文档：css-prod（生产）

> 状态（2026-07-31）：本群组资源**已由 Terraform 仓库 `css-terraform` 纳管**——免费骨架（VPC/SG/IAM/S3/ECR/SSM 壳）
> 与**堡垒机 `css-prod-bastion` 已建成在跑**；计费大件（应用机/RDS/ALB/托管 NAT）由变量 `enable_prod_compute` 门控，
> 待 Paid plan 升级后开启。**资源 ID 与操作方法以 `css-terraform/{CLAUDE.md,使用说明/}` 为准**；
> 分工见 [../新aws账号/职责划分.md](../新aws账号/职责划分.md)。
> 账号 `582797602427` / us-east-1。安全硬化逐条对照见 [../生产部署/01-独立服务器方案.md](../生产部署/01-独立服务器方案.md) §5；凭证隔离见 03-CICD §4.5。

## 1. 网络

> 网络骨架已建（现由 css-terraform `css-prod/network` stack 管理）。标签键为 **`EnvironmentGroup=css-prod` + `Environment`**（旧 `Group`/`CssEnv` 已废除）。计费资源（EC2 应用机/RDS/NAT/ALB）待 Paid plan。

| 资源 | 设计 | 资源 ID |
|------|------|---------|
| VPC `css-prod` | 10.10.0.0/16 | `vpc-0ecf70f71565ddcc8` |
| 公有子网 ×2 | 10.10.0.0/24（1a）、10.10.1.0/24（1b）；放 ALB / NAT 网关 / 堡垒机 | `subnet-08b5bf0e739ea3bb1` / `subnet-02d706c925c8d8690` |
| 私有子网 ×2 | 10.10.10.0/24（1a）、10.10.11.0/24（1b）；放应用机 + RDS | `subnet-0604379d063f292b8` / `subnet-0843756176c788fc7` |
| IGW + 路由表 | 公有 0.0.0.0/0 → IGW（`rtb-0e8f52f31b012d42b`）；私有路由 → 托管 NAT（**`enable_prod_compute` 门控待建**，`rtb-0adbc4a561ef729d1`） | `igw-03db67ff565969373` |
| S3 Gateway Endpoint | 免费 | `vpce-02df8b3c4402dcb12` |

## 2. 服务器与入口

| 资源 | 规格 | 职责 | 状态 |
|------|------|------|------|
| ALB `css-prod` | 公有子网 ×2 | 产品对外唯一入口：80（上域名+ACM 后 443；域名在 GoDaddy，不用 Route53，ACM 走手动 CNAME 验证）→ target `css-prod-app:80`；健康检查 `/`；后续可挂 WAF | ⏳ 门控待建 |
| `css-prod-app` | c5.xlarge 起（可先 c5.large 观察），私有子网，gp3 ≥50G | prod 三栈（`css-prod-{infra,backend,frontend}`），标签 `Environment=css-prod`；容器 mem_limit/cpus 限额 | ⏳ 门控待建 |
| 堡垒机 `css-prod-bastion` | t4g.micro + EIP `34.225.237.45`，公有子网 | 唯一 SSH 入口（22 ← 仅白名单 IP），常驻运行 | ✅ **已建在跑** `i-0a6d6754c61c239d0` |

## 3. 数据库

RDS `css-prod`（PostgreSQL，db.t4g.medium 起；css-terraform `css-prod/database` stack，实例本体 `enable_prod_compute` 门控，子网组已建）：**Multi-AZ + 自动备份 ≥7 天 + 存储加密 + 删除保护**，私有子网。库 **`css-prod-main`** + **`css-prod-ocr`**（`CREATE EXTENSION vector`，`docs/新aws账号/05-数据同步/create-databases.sh` 建库）。**与非生产实例完全分离**；主密码 Secrets Manager 托管（RDS 托管 secret，自动轮换）、仅运维用；应用届时走专用低权账号（`05-数据同步/create-db-accounts.sh` 创建，密码写死不轮换，改密走 `change-db-password.sh`，值只进 `/css/prod/backend.env`）。

## 4. 安全组（css-terraform 管理，ID 未变）

| SG | 入站 | ID |
|----|------|-----|
| `css-prod-alb-sg` | 80/443 ← 0.0.0.0/0 | `sg-0bc3fb67c80f4f721` |
| `css-prod-bastion-sg` | 22 ← 白名单 IP | `sg-0818a3d66a223882a` |
| `css-prod-app-sg` | 80 ← alb-sg；22 ← bastion-sg | `sg-070426ad3d37515d9` |
| `css-prod-rds-sg` | 5432 ← app-sg + bastion-sg | `sg-02d0715ea86547c15` |

## 5. IAM（本群组专属，与非生产完全独立，全部新建新密钥）

CI/CD 角色已集中到 css-terraform 的 `css-github` stack（角色名/ARN 未变）：

| 主体 | 名称 | 权限 |
|------|------|------|
| CI/CD 角色（OIDC） | `css-deploy-prod` | ECR push；SSM send-command 限 tag `Environment=css-prod`；`/css/prod/*` 参数；RDS 快照 |
| 实例角色 | `css-ec2-prod` | SSM 核心 + ECR 只读 + 读 `/css/prod/*` + CloudWatch 写 |
| 应用 S3 用户 | `css-app-prod` | 仅 prod S3 桶（Block Public Access 全开 + 加密 + 版本化） |

## 6. 配置与密钥

Parameter Store：`/css/prod/backend.env`、`/css/prod/frontend.env`。**全部密钥全新生成**（JWT_SECRET、API_KEY、中间件口令等），唯一例外 `PASSWORD_SALT`——若迁移存量用户须沿用原值。`DEBUG=0`、`SQL_ECHO=0` 强制。kafka-ui/pgadmin 默认不启。

## 7. 部署与发布

现行（2026-07-31）：`main` 分支 push → **只构建镜像**（`prod-vN` + `prod` 双 tag）；**部署 = 手动在 GitHub Actions 上 Run workflow**（充当人工闸）→ migrate（快照+alembic_version 核对）→ SSM 部署（按 tag `Environment` 定位目标机）→ 冒烟。回滚用 `prod-vN` 不可变版本 tag 重新部署。兜底：`docs/新aws账号/09-ssm-run-command/deploy-env.sh prod`。详见 [prod.md](prod.md) 与 03-CICD 文档。
