# CSS 环境总览（test / uat / prod）

> 本文件夹描述 CSS 三环境**长什么样、怎么用**：拓扑、访问方式、部署方式、现状。2026-07-31 更新。
> AWS 账号 `582797602427`（us-east-1，新账号）；与老账号 `021213872872` 的环境无关。
>
> ⚠️ **资源权威在 Terraform**：一切 AWS 资源（VPC/EC2/RDS/ALB/SG/IAM/ECR/S3/监控）自 2026-07-30 起由独立仓库
> `css-terraform/` 管理（33 个 stack，基线 = `terraform plan` 全零 diff）。资源的创建/修改/删除**只走 Terraform**
> （规范 = 其 `CLAUDE.md`；用法 = `使用说明/`、`运行命令.md`、`执行手册.md`）；Terraform 与运维脚本的分工见
> [../环境运维执行脚本/职责划分.md](../环境运维执行脚本/职责划分.md)。本文件夹与实际资源冲突时，以 css-terraform 为准。

## 文档索引

| 类别 | 文档 | 说明 |
|------|------|------|
| 环境实况 | **已迁至 `css-terraform/环境实况/`**（test/uat/prod + 两个环境组）| 随基础设施代码维护，apply 后同步更新；一致性核对 `css-terraform/scripts/check-live-facts.sh` |
| 服务技术 | [服务技术文档.md](服务技术文档.md) | 三栈架构、服务清单、配置注入模型、已知坑 |
| 价格 | [成本价格表.md](成本价格表.md) | 两群组成本明细 |
| **资源与用法（权威）** | `css-terraform/`：`CLAUDE.md`（规范）、`使用说明/`（逐组件手册）、`运行命令.md`、`执行手册.md` | 所有 AWS 资源的唯一事实源 |
| 分工 | [../环境运维执行脚本/职责划分.md](../环境运维执行脚本/职责划分.md) | Terraform 管什么、脚本管什么 |
| 运维脚本 | [../环境运维执行脚本/README.md](../环境运维执行脚本/README.md) | 镜像推送(03)、数据同步(05)、EC2 密钥(06)、IAM key(07)、CI 配置(08)、SSM 部署(09~11) |
| CI/CD | [../云服务搭建部署方案/03-CICD-GitHub-Actions.md](../云服务搭建部署方案/03-CICD-GitHub-Actions.md) / [cicd-操作手册.md](cicd-操作手册.md) | 方案与日常操作 |
| 配置值速查 | [配置速查.md](配置速查.md) | 手册/脚本要填的具体值 |
| **凭证与地址** | 工作区根 `运维访问速查.local.md`（gitignore） | 所有密码/密钥/连接串只在这里，**文档一律不抄录** |

## 环境一览

| 环境 | Git 分支 | VPC | 状态（2026-07-31） |
|------|----------|-----|------|
| test | `test` | css-non-prod | ✅ 三栈已部署（前端 200）；库已载入 preprod 数据并**已脱敏**；应用连库已切低权账号 `css_app_test`（07-30） |
| uat | `uat` | css-non-prod | 机器 / ALB / 库（`css-uat-main` 146 表，数据=test）**均已建**，应用**未部署**（ALB 返 503） |
| prod | `main` | css-prod | 堡垒机 `css-prod-bastion` ✅ 在跑；应用机/RDS/ALB/NAT 由 `enable_prod_compute` 门控，等 Paid plan |

## 总拓扑（2026-07-31）

```
                你的开发 IP 221.214.0.190（管理白名单，kafka-ui 另加 134.195.101.194）
                                   │ SSH/HTTP
        ┌──────────────────────────┼──────────────────────────────┐
        ▼                          ▼                              ▼（公网用户）
┌─ VPC css-non-prod (10.20.0.0/16) ──────────────┐   ┌─ VPC css-prod (10.10.0.0/16) ─────────┐
│ 公有子网×2                                      │   │ 公有子网×2                             │
│   ALB css-test ✅ ┃ ALB css-uat ✅              │   │   ALB css-prod ⏳（门控）               │
│   开发入口 ALB css-non-prod-entry ✅            │   │   NAT 网关 ⏳（门控）                   │
│   （kafka-ui：test :8085 / uat :8086，白名单）   │   │   堡垒机 css-prod-bastion ✅            │
│   堡垒机 css-non-prod-bastion                   │   │   + EIP 34.225.237.45（仅 22）          │
│   + EIP 3.225.148.166（堡垒 22 ┃ NAT 出网）      │   │                                       │
│ 私有子网×2                                      │   │ 私有子网×2                             │
│   EC2 css-test-app 10.20.10.10 ✅               │   │   EC2 prod ⏳（门控）                   │
│   EC2 css-uat-app  10.20.11.10 ✅（未部署）      │   │   RDS css-prod ⏳（门控，Multi-AZ）     │
│   RDS css-non-prod（PG16.14，删除保护开）✅      │   │     css-prod-main / css-prod-ocr       │
│     css-test-main/-ocr ┃ css-uat-main/-ocr      │   │                                       │
└─────────────────────────────────────────────────┘   └───────────────────────────────────────┘
   每 VPC：S3 Gateway Endpoint（免费）；CI/CD 经 SSM Run Command 直达私网应用机，不经堡垒机
   S3：css-{test,uat,prod,dev}-582797602427 + 运维中转桶 css-dbsync-582797602427（共 5 个）
```

- 堡垒机 `css-non-prod-bastion` 原名 `css-non-prod-gw`，2026-07-30 改名（实例 `i-08b0ef319d08eae38`、EIP 不变；
  本机密钥文件名沿用 `css-non-prod-gw.pem`）；
- 应用机 2026-07-30 由 Terraform 重建（实例 ID 变了：test=`i-0cb9b69b9eb19a9aa`、uat=`i-0f90c5c061d640a27`；
  KeyName 改为各自专属钥 `css-test`/`css-uat`，根卷已加密，私网 IP 不变）。

**关键规则**：

1. **SSH 只能经堡垒机**：nonprod=`css-non-prod-bastion`（3.225.148.166）、prod=`css-prod-bastion`（34.225.237.45）；
   22 仅放行管理 IP。开发者临时钥（带过期）走 `docs/环境运维执行脚本/06-服务器密钥与访问/grant-dev-ssh.sh`；
2. **系统 Web 只经本环境 ALB**（`css-test` / `css-uat` / `css-prod`⏳，名字=环境名）；
   **kafka-ui 只走开发入口 ALB** `css-non-prod-entry`（test :8085 / uat :8086，仅白名单
   `221.214.0.190/32` + `134.195.101.194/32`），业务 ALB 的 8085 监听器已全部撤除；
3. **RDS 只能内网访问**：`--no-publicly-accessible`，`css-non-prod-rds-sg` 仅放行各环境 app-sg 与堡垒机 SG；
4. **安全组每环境独立**（2026-07-30 拆分）：`css-test-app-sg` / `css-test-alb-sg` / `css-uat-app-sg` / `css-uat-alb-sg`；
   旧共用的 `css-non-prod-app-sg` / `css-non-prod-alb-sg` 已删除；
5. **标签键 = `EnvironmentGroup` + `Environment`**（旧 `Group`/`CssEnv` 已彻底删除）。`Environment` 是控制面标签：
   SSM 部署与 IAM 条件按它定位目标机，组内共享资源必须打 `css-shared`；
6. ECR 仓库每环境独立（`<env>/css-xxx`，21 个，lifecycle 保 5）；镜像 tag `<env>-vN`（版本）+ `<env>`（浮动）；
7. 环境变量唯一事实源：SSM Parameter Store `/css/<env>/{backend,frontend}.env`（Terraform 只管**壳**，
   值走 `11-parameter-store/put-params.sh` 或控制台推送）；
8. 数据库账号：应用一律用低权账号 `css_app_<env>`（密码固定不轮换，改密走 `05-数据库运维/change-db-password.sh`）；
   master `postgres` 仅运维用（Secrets Manager 托管，**7 天**自动轮换）；本地开发用 `css_dev`；
9. 域名不用 Route53（DNS 留在 GoDaddy，将来 ACM 走手动 CNAME 验证）；HTTPS 尚未启用；
10. 非生产导入真实数据后必须脱敏（`05-数据库运维/anonymize-db.sh`）；每次 restore/sync 后必须重跑
    `reown-db-objects.sh` 移交对象 owner。

## 成本与预算

- 预算 `css-daily-cost`：上限 **$50/日**，超 **$30 / $50** 两档邮件告警 → `charles@shinypathway.com` + `2219002126@qq.com`；
  CloudWatch 的 SNS 告警订阅同两邮箱（订阅已发起，**待收件人点确认邮件**）；
- 账号仍为 **Free plan**：prod 计费大件（RDS/应用机/NAT/ALB）与 RDS 升配均被拦截，全部挂
  `enable_prod_compute` 门控，升 Paid plan 后按 `css-terraform/运行命令.md` 一次性开闸；
- 成本明细见 [成本价格表.md](成本价格表.md)。

## 已知临时债（2026-07-31）

| 项 | 说明 |
|----|------|
| S3 对象公有读 | test/uat/prod 三桶临时开了对象公读（桶策略型），代码接入 presigned URL 后回收 |
| SNS 订阅待确认 | 告警邮箱订阅处于 PendingConfirmation，收件人未点确认前告警发不出去 |
| HTTPS 未开 | ALB 仅 80；ACM/GoDaddy CNAME 流程见 css-terraform CLAUDE.md §十二 |
| 前端 16 个 tsc 类型错误 | 构建走 `Dockerfile.novalidate` 跳过 tsc，修完后应恢复 `npm run build` |
