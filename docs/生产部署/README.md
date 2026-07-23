# CSS 生产环境部署方案 — 索引

> 目标：基于现有 **preprod** 运行形态，部署一套**生产（prod）环境**，并系统性规避[安全与架构审计](../../审计报告/)发现的问题；**数据库（RDS）独立部署**。
> 本目录只产出**方案文档**，不创建任何 AWS 资源（用户 2026-07-23 明确"先给方案，不要创建"）。域名走**我方统一分配的子域名** + ACM 证书 HTTPS 终止。
> 编制日期：2026-07-23。基线：v20260705 代码 + 现有 `部署包/` 三栈工具链（test/uat 已跑通）。

## 两套方案

| 方案 | 定位 | 文档 |
|------|------|------|
| 方案一：独立服务器 + ECR CI/CD | **初步方案**（落地快、改动小）：单台 EC2 承载应用与自托管中间件，RDS 独立，复用并扩展现有 `部署包/` 三栈，按审计逐条硬化 | [01-独立服务器方案.md](01-独立服务器方案.md) |
| 方案二：Serverless 优化 | **优化方案**（去自托管、按需伸缩、可观测）：前端 CloudFront、后端 Fargate、队列 Kafka→**SQS**、RabbitMQ→Amazon MQ、Redis→ElastiCache、cron→EventBridge | [02-Serverless优化方案.md](02-Serverless优化方案.md) |
| CI/CD：GitHub Actions | **两套方案共用**：GitHub Actions 触发打包（build+push ECR）与部署（SSM/ECS），OIDC 免静态密钥、Environments 审批、不可变镜像 tag | [03-CICD-GitHub-Actions.md](03-CICD-GitHub-Actions.md) |

建议路径：**先用方案一上线**（复用已跑通的工具链，最快拿到合规、可用的生产环境），再按方案二**分阶段演进**（每阶段独立可回退）。两套方案的 CI/CD 均由 **GitHub Actions** 触发。

## 关键前提（已确认 / 待确认）

- ✅ **只出方案不创建**：本文档为规划稿，AWS 资源创建、Terraform 编写属后续执行阶段。
- ✅ **域名**：我方统一分配 prod 子域名（如 `app.<prod>.example.com`），Route 53 托管 + ACM 证书。
- ✅ **RDS 独立部署**：prod 用**独立 RDS 实例**（不与 test/uat 的 `css-non-prod` 共用），Multi-AZ + 自动备份。
- ⏳ **AWS 账号/区域（待你最终拍板，方案默认取"沿用 582797602427 + prod 资源硬隔离"）**：
  - 推荐 A：沿用 `582797602427`，新建 prod 专属 VPC/RDS/S3/IAM，与 test/uat 硬隔离（最省事，复用现有 ECR 与部署包）；
  - 更稳 B：新建独立 prod 账号（Organizations 分账），与非生产、与客户旧账号 `021213872872` 彻底隔离（审计推荐，但需配跨账号 ECR/权限）。
  - 区域默认 `us-east-1`（与非生产一致）；若 Ocean Island 有欧洲数据合规要求则改 `eu-central-1`。

## 与现状的关系

- **参照环境 preprod**（客户账号 `021213872872` / eu-central-1）是唯一经 SSH 深度核实的运行环境：单台 c5.xlarge、22 个容器（含容器化 DB、CI runner、pgadmin/kafka-ui 公网开放），是**问题的集中体现**，不能照搬。
- **现有非生产工具链 `部署包/`**（我方账号 `582797602427`）已经修好了 preprod 的一大半架构问题（RDS 独立、无 db 容器、默认不发布 pgadmin/kafka-ui、每环境独立 S3 桶、EC2 只 pull 用实例角色拉 ECR）。**方案一 = 把这套工具链扩展到 prod + 补齐生产级硬化**（ALB/TLS/WAF、RDS Multi-AZ、Secrets Manager、SSM 免开 22、不可变镜像 tag、CI 不落在业务机、日志监控）。

## 相关文档

- [审计报告/](../../审计报告/)：安全与架构审计（67 条代码发现 + 基础设施/CICD/密钥问题），本方案的硬化项逐条对应。
- [部署包/README-手册.md](../../部署包/README-手册.md)：现有三栈部署工具链手册。
- [功能列表 §六 技术债与生产化优化](../ocean-island/功能列表.md)：本方案涉及的代码级技术债（bug 修复、S3 隔离、队列转 SQS、日志监控）已登记为功能项。
