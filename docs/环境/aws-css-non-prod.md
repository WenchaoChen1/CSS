# AWS 群组文档：css-non-prod（非生产：test + uat）

> 状态：**网络/IAM 骨架、网关机、RDS `css-non-prod` 均已建成（2026-07-28）**；test/uat 应用机待建（`docs/新aws账号/06-ec2/create-app-ec2.sh`）。资源 ID 列随创建回填。
> 账号 `582797602427` / us-east-1。凭证隔离原则见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md) §4.5。

## 1. 网络

> 网络与 IAM 骨架 **2026-07-28 已创建**（脚本：工作区 `docs/新aws账号/01-vpc/create-vpc.sh`、`docs/新aws账号/07-iam/create-iam.sh`，幂等可重跑）。所有资源带标签 `Group=css-non-prod`。

| 资源 | 设计 | 资源 ID |
|------|------|---------|
| VPC `css-non-prod` | 10.20.0.0/16，DNS 主机名开启 | `vpc-014be109b904d6a07` |
| 公有子网 ×2 | 10.20.0.0/24（1a）、10.20.1.0/24（1b）；放网关机 | `subnet-05e2714c662a7a09a` / `subnet-08c98e86180963b12` |
| 私有子网 ×2 | 10.20.10.0/24（1a）、10.20.11.0/24（1b）；放 test/uat 应用机 + RDS | `subnet-04a93307191b196df` / `subnet-0ae9a401f7019cd69` |
| IGW + 公有路由表 | 0.0.0.0/0 → IGW | `igw-0aab6c7e645cf8d5e` / `rtb-0dc10ddb89b0b9a4b` |
| 私有路由表 | 0.0.0.0/0 → 网关机 ENI（网关机 `i-08b0ef319d08eae38` ✅ 已建） | `rtb-09e52c1f686601034` |
| S3 Gateway Endpoint | 免费，S3 流量不出 NAT | `vpce-0d9f563d331e2d8ee` |

## 2. 服务器

| 机器 | 规格 | 子网 | 职责 | 状态 |
|------|------|------|------|------|
| 网关机 `css-nonprod-gw` | t4g.micro（Amazon Linux 2023 arm64）+ EIP `3.225.148.166` | 公有 | ① 堡垒（22，SSH 唯一入口）② NAT（iptables masquerade）③ nginx 反代（:80→test:80、:8080→uat:80，**过渡通道**，ALB 就绪后收掉）；instance profile `css-gw-nonprod`（SSM + 读 css-dbsync 桶 + 读 rds! secret，无 CssEnv 标签） | ✅ `i-08b0ef319d08eae38` |
| `css-test-app` | t3.large（2c8G，gp3 50G） | 私有 | test 三栈（`css-test-{infra,backend,frontend}`），标签 `CssEnv=css-test` | ⏳ 待建（06-ec2） |
| `css-uat-app` | t3.large（2c8G，gp3 50G） | 私有 | uat 三栈，标签 `CssEnv=css-uat` | ⏳ 待建（06-ec2） |

> 旧默认 VPC 的 test 机 `i-08e110b5a5425980d`（100.30.61.207）已于 2026-07-28 删除、EIP 已释放；当前账号无任何应用机。

## 3. 数据库

实例 **`css-non-prod`**（✅ 2026-07-28 已在新 VPC 建成，`docs/新aws账号/04-rds/create-rds.sh nonprod` 创建；旧默认 VPC 同名实例已删除）：

| 项 | 值 |
|----|-----|
| Endpoint | `css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com` |
| 引擎/规格 | PostgreSQL **16.14** / db.t4g.micro，单 AZ |
| Master 用户 | `postgres`（密码 Secrets Manager 托管，`rds!` secret） |
| 网络 | 私有子网、`--no-publicly-accessible`，SG 仅放行 app/网关 SG（仅内网访问） |
| 库 | `css-test-main` / `css-test-ocr` ✅ 已从 preprod 备份载入（含 pgvector）；`css-uat-main` / `css-uat-ocr` ⏳ 待建（`create-databases.sh`，ocr 库自动加 pgvector） |

数据恢复走 `docs/新aws账号/05-数据同步/restore-dump-via-gw.sh`：本地 `pg_dump -Fc` 备份 → S3 中转桶 `css-dbsync-<账号>` → SSM 在网关机装 psql16、自取 Secrets Manager 密码、建库（+pgvector）、`pg_restore`、清理。⚠️ 数据库版本注意：导数据前核对源/目标 PG 大版本（本实例 PG16），`pg_dump`/`pg_restore` 客户端版本不得低于服务端大版本；跨大版本恢复前先在测试库演练。env 中 `POSTGRES_DB`、`OCR_*_URL` 使用新库名。

## 4. 安全组

| SG | 入站 | 出站 | ID |
|----|------|------|-----|
| `css-nonprod-gw-sg` | 22, 80, 8080 ← `221.214.0.190/32`；全部 ← 10.20.0.0/16（NAT 回程） | all | `sg-0cb64524667184295` |
| `css-nonprod-app-sg`（test/uat 共用） | 80 ← gw-sg；22 ← gw-sg | all（经网关 NAT） | `sg-0cfa6a7448f3bb95c` |
| `css-nonprod-rds-sg` | 5432 ← app-sg + gw-sg（**仅内网**，RDS 不可公网访问） | — | `sg-035acf1546045ba88` |
| `css-nonprod-alb-sg` | 80/443 ← 0.0.0.0/0（ALB 用；ALB 待应用机+域名后创建，脚本 `docs/新aws账号/12-alb/`） | all | `sg-0c8f420e1e46b5b4b` |

## 5. IAM（本群组专属，与 prod 群组完全独立）

✅ 已创建（OIDC provider：`arn:aws:iam::582797602427:oidc-provider/token.actions.githubusercontent.com`）：

| 主体 | 名称 | 权限 |
|------|------|------|
| CI/CD 角色（OIDC） | `css-deploy-test` / `css-deploy-uat` | ECR push；SSM send-command 限 `CssEnv=css-test|css-uat` 标签实例；参数 `/css/test/*` 或 `/css/uat/*`；uat 加 RDS 快照；信任两仓库对应分支与 GitHub Environment |
| 实例角色（含 instance profile） | `css-ec2-test` / `css-ec2-uat` | AmazonSSMManagedInstanceCore + ECR 只读 + 读本环境参数 |
| 应用 S3 用户 | `css-app-test` / `css-app-uat` | 仅本环境 S3 桶；AK/SK 只进本环境 Parameter Store（key 待填值阶段生成） |
| 网关机 instance profile | `css-gw-nonprod` | SSM 托管核心 + 读 S3 中转桶 `css-dbsync-*` + 读 RDS `rds!` secret（Secrets Manager）；**无 CssEnv 标签**（不是部署目标） |

> 旧默认 VPC test EC2（`i-08e110b5a5425980d`，角色 `css-non-prod-ec2-role`）曾作为过渡期部署目标，**已于 2026-07-28 删除**；CI/CD 部署目标改为新 VPC 待建的应用机。

## 6. 配置与密钥

Parameter Store（SecureString）：`/css/test/backend.env`、`/css/test/frontend.env`、`/css/uat/backend.env`、`/css/uat/frontend.env`。test 已灌入（本地底稿：工作区根 `deploy-env/test/`，与两代码仓库同级，不入库）；uat 以 `deploy-env/uat/*.example` 为底稿填值。耦合键（`API_KEY==VITE_X_API_KEY` 等）由 CI 校验。（EC2 上 `/opt/css-cicd/env/<env>/` 为部署时的运行时渲染路径，与本地底稿无关。）

## 7. 访问速查

网关 EIP = `3.225.148.166`。访问三条铁律：SSH 只经堡垒机（网关机）；Web 最终只走 ALB 域名（下面 nginx 反代为过渡通道）；RDS 仅内网。

```
test 页面   http://3.225.148.166/          （仅 221.214.0.190；过渡通道，ALB 就绪后收掉）
uat  页面   http://3.225.148.166:8080/     （仅 221.214.0.190；过渡通道）
SSH        ssh -J ec2-user@3.225.148.166 ec2-user@<私网IP>
RDS        ssh -L 5432:css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432 ec2-user@3.225.148.166 → 本地 psql
```
