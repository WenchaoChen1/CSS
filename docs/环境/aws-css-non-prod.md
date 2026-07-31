# AWS 群组文档：css-non-prod（非生产：test + uat）

> 状态（2026-07-31）：本群组**全部 AWS 资源已由 Terraform 仓库 `css-terraform` 纳管**（plan 全零 diff）。
> **资源清单、ID、参数与操作方法一律以 `css-terraform/{CLAUDE.md,使用说明/,运行命令.md,执行手册.md}` 为准**；
> Terraform 与内部脚本的分工见 [../新aws账号/职责划分.md](../新aws账号/职责划分.md)。
> 本页只保留环境组概览与常用事实速查。账号 `582797602427` / us-east-1。
> 凭证与连接命令见工作区 `运维访问速查.local.md`（gitignore，本文档不抄录）。

## 1. 概览

- VPC `css-non-prod`（10.20.0.0/16），公有/私有子网各 2（跨 1a/1b）；test/uat 共享 VPC 与 RDS 实例，
  其余（EC2/ALB/ECR/IAM/SG/SSM/S3/监控）**按环境独立**。资源 ID 见 css-terraform `使用说明/01-网络.md`。
- 出网：堡垒机自建 NAT（iptables）；S3 走 Gateway Endpoint。

## 2. 服务器（2026-07-30 应用机重建，ID 已变）

| 机器 | 实例 ID | 私网 IP | 说明 |
|------|---------|---------|------|
| 堡垒机 `css-non-prod-bastion`（原名 `css-non-prod-gw`，07-30 改名） | `i-08b0ef319d08eae38` | 10.20.0.74（EIP `3.225.148.166`） | 堡垒 SSH + NAT 出网两件事；**不是部署目标**。本机私钥文件名沿用 `~/.ssh/css-non-prod-gw.pem` |
| `css-test-app` | `i-0cb9b69b9eb19a9aa` | **10.20.10.10** | m7i-flex.large，key pair `css-test`，根卷已加密；三栈已部署 |
| `css-uat-app` | `i-0f90c5c061d640a27` | **10.20.11.10** | m7i-flex.large，key pair `css-uat`，根卷已加密；**已建机未部署** |

## 3. 数据库（RDS `css-non-prod`）

- PG **16.14** / db.t4g.micro / 单 AZ / 私有子网仅内网 / **删除保护已开**；endpoint 见 `运维访问速查.local.md`。
- 库：`css-test-main` / `css-test-ocr`（已载 preprod 数据并脱敏）；`css-uat-main`（146 表 / 188 用户，=test 数据）/ `css-uat-ocr` ✅ 已建。
- 库账号（2026-07-30 起）：`css_app_test`（test 应用现用它连库）/ `css_app_uat` / `css_dev`（可建新库 + test/uat 四库读写，删不了存量库）/ `css_ops`（rds_superuser）。
  自建账号密码写死不轮换，改密走 `docs/新aws账号/05-数据库运维/change-db-password.sh`。
- master `postgres` **仅运维用**，密码 Secrets Manager 托管、**7 天自动轮换**（此前文档误写 90 天，以 7 天为准）。
- 升配 db.t4g.small 仍被 Free plan 拦截（瓶颈是内存不是 CPU），升 Paid 后改 css-terraform `database` stack 的实例规格变量执行。
- 数据操作（建库/同步/恢复/脱敏/账号）走 `docs/新aws账号/05-数据库运维/`（不属 Terraform 管辖）。

## 4. 安全组（2026-07-30 起每环境独立，旧共用组已删）

| SG | ID |
|----|-----|
| `css-non-prod-bastion-sg`（原 `css-non-prod-gw-sg` 已删） | `sg-0b0a1508e6063d23f` |
| `css-test-app-sg` / `css-test-alb-sg` | `sg-0ece87f7087c3b6d9` / `sg-090abd4ac21053904` |
| `css-uat-app-sg` / `css-uat-alb-sg` | `sg-0bf1d8adaf6e4a0e6` / `sg-0d02ba42b56aea851` |
| `css-non-prod-rds-sg` | `sg-0197c0db4578107ef` |
| `css-non-prod-entry-sg`（开发入口 ALB） | `sg-0dc5c5ed025c07a76` |

规则细节以 css-terraform 各环境 `sg` stack 为准。堡垒机 SG 的 `10.20.0.0/16 全协议`入站是 **NAT 回程**，删了 test/uat 立即断网。

## 5. 入口（ALB）

| ALB | DNS | 用途 |
|-----|-----|------|
| `css-test` | `css-test-524317374.us-east-1.elb.amazonaws.com` | test 业务入口（前端实测 200） |
| `css-uat` | `css-uat-1366981991.us-east-1.elb.amazonaws.com` | uat 业务入口（未部署，503 属正常） |
| `css-non-prod-entry` | `css-non-prod-entry-1482605872.us-east-1.elb.amazonaws.com` | **开发访问入口**：kafka-ui（test `:8085` / uat `:8086`），白名单 `221.214.0.190/32` + `134.195.101.194/32` |

- 业务 ALB 的 8085 已全部撤除，kafka-ui 只走开发入口 ALB。
- 域名不走 Route53（在 GoDaddy，未来 ACM 手动 CNAME 验证）；HTTPS 未开。

## 6. S3

- 应用桶一环境一个：`css-test-582797602427` / `css-uat-582797602427` / `css-prod-582797602427`；本地开发桶 `css-dev-582797602427`（已入 TF）；运维中转桶 `css-dbsync-582797602427`（未纳管）。
- ⚠️ **临时债**：test/uat/prod 三桶已开**对象公有读**（2026-07 权宜），改 presigned URL 后回收。

## 7. 标签 / 监控 / 预算

- 标签键（2026-07-30 全量切换）：**`EnvironmentGroup`（css-non-prod|css-prod）+ `Environment`（css-test|css-uat|css-prod|…）**，旧 `Group`/`CssEnv` 已彻底删除；SSM 部署与 IAM 条件按 `Environment` 定位目标机。
- CloudWatch：test/uat 各 9 告警 + Dashboard + SNS（由 css-terraform `monitoring` stack 管理）；SNS 告警已订阅 `charles@shinypathway.com` + `2219002126@qq.com`（订阅确认状态待核实）。
- 预算 `css-daily-cost`：上限 $50，>$30 / >$50 两档邮件发同上两邮箱。

## 8. 访问

三条铁律不变：SSH 只经堡垒机；Web 只经本环境 ALB（kafka-ui 走开发入口 ALB）；RDS 仅内网。
具体 SSH / 隧道 / psql 命令与全部凭证见工作区 `运维访问速查.local.md`。
开发者临时 SSH 用 `docs/新aws账号/06-服务器密钥与访问/grant-dev-ssh.sh`（到期 `revoke-dev-ssh.sh` 回收）。
