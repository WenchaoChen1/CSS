# AWS 群组文档：css-prod（生产）

> 状态：**网络与 IAM 骨架已建（2026-07-28），计费资源待 Paid plan 升级后创建（阶段三）**。
> 账号 `582797602427` / us-east-1。安全硬化逐条对照见 [../生产部署/01-独立服务器方案.md](../生产部署/01-独立服务器方案.md) §5；凭证隔离见 03-CICD §4.5。

## 1. 网络

> 网络与 IAM 骨架 **2026-07-28 已创建**（脚本同非生产）。所有资源带标签 `Group=css-prod`。计费资源（EC2/RDS/NAT/ALB）待 Paid plan 升级。

| 资源 | 设计 | 资源 ID |
|------|------|---------|
| VPC `css-prod` | 10.10.0.0/16 | `vpc-0ecf70f71565ddcc8` |
| 公有子网 ×2 | 10.10.0.0/24（1a）、10.10.1.0/24（1b）；放 ALB / NAT 网关 / 堡垒机 | `subnet-08b5bf0e739ea3bb1` / `subnet-02d706c925c8d8690` |
| 私有子网 ×2 | 10.10.10.0/24（1a）、10.10.11.0/24（1b）；放应用机 + RDS | `subnet-0604379d063f292b8` / `subnet-0843756176c788fc7` |
| IGW + 路由表 | 公有 0.0.0.0/0 → IGW（`rtb-0e8f52f31b012d42b`）；私有路由 → NAT 网关（**待建后补**，`rtb-0adbc4a561ef729d1`） | `igw-03db67ff565969373` |
| S3 Gateway Endpoint | 免费 | `vpce-02df8b3c4402dcb12` |

## 2. 服务器与入口

| 资源 | 规格 | 职责 |
|------|------|------|
| ALB `css-prod-alb` | 公有子网 ×2 | 产品对外唯一入口：80（上域名+ACM 后 443）→ target `css-prod-app:80`；健康检查 `/`；后续可挂 WAF |
| `css-prod-app` | c5.xlarge 起（可先 c5.large 观察），私有子网，gp3 ≥50G | prod 三栈（`css-prod-{infra,backend,frontend}`），标签 `CssEnv=css-prod`；容器 mem_limit/cpus 限额 |
| 堡垒机 `css-prod-bastion` | t4g.nano + EIP，公有子网 | 唯一 SSH 入口（22 ← 仅 `221.214.0.190/32`），平时可 stop |

## 3. 数据库

RDS `css-prod`（PostgreSQL，db.t4g.medium 起，`docs/新aws账号/04-rds/create-rds.sh prod` 创建）：**Multi-AZ + 自动备份 ≥7 天 + 存储加密 + 删除保护**，私有子网。库 **`css-prod-main`** + **`css-prod-ocr`**（`CREATE EXTENSION vector`，`docs/新aws账号/05-数据同步/create-databases.sh` 建库）。**与非生产实例完全分离**；主密码 Secrets Manager 托管，应用走专用低权账号 `css_app`（密码在 `/css/prod/backend.env`，不参与轮换）。

## 4. 安全组

| SG | 入站 | ID |
|----|------|-----|
| `css-prod-alb-sg` | 80/443 ← 0.0.0.0/0 | `sg-0bc3fb67c80f4f721` |
| `css-prod-bastion-sg` | 22 ← `221.214.0.190/32` | `sg-0818a3d66a223882a` |
| `css-prod-app-sg` | 80 ← alb-sg；22 ← bastion-sg | `sg-070426ad3d37515d9` |
| `css-prod-rds-sg` | 5432 ← app-sg + bastion-sg | `sg-02d0715ea86547c15` |

## 5. IAM（本群组专属，与非生产完全独立，全部新建新密钥）

| 主体 | 名称 | 权限 |
|------|------|------|
| CI/CD 角色（OIDC） | `css-deploy-prod` | ECR push；SSM send-command 限 `CssEnv=css-prod`；`/css/prod/*` 参数；RDS 快照 |
| 实例角色 | `css-ec2-prod` | SSM 核心 + ECR 只读 + 读 `/css/prod/*` + CloudWatch 写 |
| 应用 S3 用户 | `css-app-prod` | 仅 prod S3 桶（Block Public Access 全开 + 加密 + 版本化） |

## 6. 配置与密钥

Parameter Store：`/css/prod/backend.env`、`/css/prod/frontend.env`。**全部密钥全新生成**（JWT_SECRET、API_KEY、中间件口令等），唯一例外 `PASSWORD_SALT`——若迁移存量用户须沿用原值。`DEBUG=0`、`SQL_ECHO=0` 强制。kafka-ui/pgadmin 默认不启。

## 7. 部署与发布

`main` 分支 push → 构建自动 → **GitHub Environment `production` 人工审批** → migrate（快照+alembic_version 核对）→ SSM 部署 → 冒烟。回滚用 `prod-vN` 不可变版本 tag。（⚠️ 现阶段 CI 只推镜像，migrate/deploy job 已注释；部署 = 手动 `docs/新aws账号/09-ssm-run-command/deploy-env.sh prod`。）详见 [prod.md](prod.md) 与 03-CICD 文档。
