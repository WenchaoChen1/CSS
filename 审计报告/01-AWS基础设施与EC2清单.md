# 01 · 客户 AWS 用了什么 · 有什么问题

> 客户账号 `021213872872`（IAM 用户 `Dev`）· 区域 **eu-central-1(法兰克福)** · 全部经只读枚举，未改动任何资源。

---

## 一、用了哪些 AWS 服务

| 服务 | 用途 | 规模/细节 |
|------|------|-----------|
| **EC2** | 承载 dev/preprod/stage 全栈（应用 + 中间件容器） | 4 台 c5.xlarge（3 running，1 stopped） |
| **Elastic IP** | 固定运行实例公网 IP | 共 7 个，**仅 3 个挂载，4 个闲置计费** |
| **S3** | 文件存储 + Terraform 远程状态 | `chain-serve-test`、`chain-service-solutions-uat`、`devteam-css-terraform-state` |
| **SES** | 发信（no-reply@chain-serve.com 等） | 十余个已验证身份（含大量 yopmail 测试地址） |
| **IAM** | 用户/CI/IaC 凭据 | 8 个用户 |
| **VPC** | 网络 | 默认 VPC `172.31.0.0/16`（实例实际所在）+ 自建 `10.0.0.0/16`（scrivas 用） |

**明确未使用**（决定了架构特征）：
- ❌ **RDS**（无托管数据库）→ Postgres 是 EC2 上的容器
- ❌ **ElastiCache**（无托管 Redis）→ Redis 是容器
- ❌ **ALB/NLB/CLB**（无负载均衡）→ 直接暴露 EC2 上 nginx 端口
- ❌ **Secrets Manager**（无托管密钥）→ 密钥靠 GitLab CI 变量 + 明文 .env
- ❌ **CloudFront / WAF**（无 CDN/边缘防护）

> **架构判断**：这是一套 **"EC2 单机 + 全容器" 的自托管架构**，几乎不用 AWS 托管服务；每台 EC2 自带一整套 DB+缓存+消息队列容器，环境之间独立。
>
> 补充：该账号还并存另一个产品 **scrivas**（EKS/k8s + ECR `scrivas/*`，自建 VPC 10.0.0.0/16）。chain-serve 与 scrivas **共用同一 AWS 账号**，计费与权限边界混在一起。

---

## 二、EC2 实例清单

| 环境 | 实例 ID | 类型 | 公网 IP | 私网 IP | 状态 | 关联安全组 |
|------|---------|------|---------|---------|------|-----------|
| dev | `i-072a709f0205514e3` | c5.xlarge | 3.124.149.172 | 172.31.28.222 | running | `sg-0a19d84dec8d1a9fe`(launch-wizard-4) |
| dev(旧) | `i-0c70127b8fa8bfb54` | c5.xlarge | — | 172.31.32.194 | **stopped** | `sg-0a44…` + `sg-06fdee…` |
| **preprod** | `i-08f640a82749cffdf` | c5.xlarge | 3.74.51.100 | 172.31.17.96 | running | `sg-037aa246d4c48a182`(launch-wizard-3) |
| stage | `i-02d75a88344591383` | c5.xlarge | 52.28.87.199 | 172.31.43.30 | running | `sg-0a44302cb26b3d92e`(css-sg-2025…) |

- 全部 **c5.xlarge（4 vCPU / 8GB）**、eu-central-1、跑在**默认 VPC**。**没有名为 prod 的实例**（环境是 dev/preprod/stage；preprod 运行时 `ENV=prod`，承担准生产角色）。

---

## 三、🔴 安全组问题（重点）

### 每台运行实例的入站规则（全部来源 `0.0.0.0/0` = 全网）

| 实例 | 安全组 | 对全网开放的端口 |
|------|--------|------------------|
| **preprod** | `sg-037aa246d4c48a182` (launch-wizard-3) | **22(SSH)、80、443、8005(kafka-ui)、8006(pgadmin)** |
| **dev** | `sg-0a19d84dec8d1a9fe` (launch-wizard-4) | **22、80、443、7432(Postgres)、8005、8006** |
| **stage** | `sg-0a44302cb26b3d92e` (css-sg-2025…) | **22、80、443、7432(Postgres)、8005、8006** |

### 问题清单

| 级别 | 问题 | 说明 |
|------|------|------|
| 🔴 CRITICAL | **数据库管理台 pgadmin(8006) 对全网开放** | 三台机器都把 8006 开给 `0.0.0.0/0`，任何人可访问 DB 管理界面（口令见 [05](05-环境变量与密钥审计.md)，且是明文弱口令）。 |
| 🔴 CRITICAL | **dev/stage 的 Postgres 端口 7432 对全网开放** | 数据库直接暴露公网，配合默认 `postgres` 超级用户/弱口令 → 数据库可被直接连接/爆破。 |
| 🔴 CRITICAL | **kafka-ui(8005) 对全网开放** | 消息队列管理界面（含 2FA 短信验证码 topic）公网可达。 |
| 🟠 HIGH | **SSH(22) 对全网开放** | 三台机器 22 端口 `0.0.0.0/0`，仅靠密钥兜底；应收敛到跳板/办公 IP。 |
| 🟠 HIGH | **账号内存在 `ALL/ALL 0.0.0.0/0` 的安全组** | `sg-060a6a4c69c15dd38`(launch-wizard-2) 放行**所有协议所有端口**给全网；`sg-03121a4b…`(launch-wizard-1) 开 22/80/443 给全网。虽未挂在当前运行的 CSS 实例上，但存在即隐患，随时可能被误挂。 |
| 🟡 MEDIUM | **安全组是 launch-wizard 手工创建，未纳入 IaC** | 名字 `launch-wizard-1/2/3/4` 说明是控制台向导随手建的，规则重复、无版本管理、难审计。对比同账号 scrivas 的 k8s 安全组用的是**安全组间引用（sg→sg）**的最小授权，规范得多——CSS 这套明显是"图省事全开"。 |
| 🟡 MEDIUM | **Terraform 里的 staging 安全组（`css-staging-…` sg-06fdee）无入站规则**，实际生效的却是手工 launch-wizard 组 → IaC 与现实脱节。 |

> **建议**：8006/8005/7432 一律**关闭公网**，改走 SSH 隧道/跳板或内网；22 收敛到固定 IP；删除 `ALL/ALL` 全开安全组；用 Terraform 统一纳管，按端口最小化授权。

---

## 四、S3 与公开访问（验证了代码里的 public-read 是真生效）

| 桶 | Public Access Block | 桶策略 |
|----|---------------------|--------|
| `chain-serve-test` | **全部 false（未阻断公开）** | 无 |
| `chain-service-solutions-uat` | **全部 false（未阻断公开）** | 无 |

- 两个业务桶的 **S3 Public Access Block 四项全部关闭**（`BlockPublicAcls/IgnorePublicAcls/BlockPublicPolicy/RestrictPublicBuckets` 均 false）。
- 这**坐实了代码审计 #10**：后端上传对象硬编码 `default_acl='public-read'`，而桶层面没有拦截 → **发票/客户文件/报表以永久公开 URL 世界可读**。
- 🔴 **建议**：开启 S3 Public Access Block（至少 `IgnorePublicAcls=true`）+ 后端去掉 `public-read` 改私有 + 预签名 URL。

---

## 五、IAM 现状与问题

| 用户 | Access Key | 创建 | 备注 |
|------|-----------|------|------|
| `css-bucket` | AKIA…WASXPHO | 2024-01-11 | **1.5 年未轮换**；即部署里 S3 用的凭据 |
| `Dev` | AKIA…GQG7J65 | 2026-07-15 | 本次审计用，**已在聊天出现，务必轮换** |
| `egor.kovalev` / `jialiaz3` | 各 1 把 | 2025 | 开发者个人长期 key |
| `gitlab` | AKIA…OO6DYV6 | 2025-09-12 | CI 用（推镜像/S3/SES） |
| `Oleksii` | **2 把 active** | 2025-10 / 12 | **轮换未闭环** |
| `terraform` | AKIA…URUXLN4 | 2025-08-18 | IaC 用 |
| `ses-smtp-user…` | — | 2024-01-16 | SES SMTP 发信 |

**问题**：长期静态 key（css-bucket 1.5 年）、`Oleksii` 双 active key、开发者用个人 AK/SK 直连、无 Secrets Manager、密钥靠明文 .env 流转。

---

## 六、成本与卫生

- **4 个闲置 Elastic IP**（18.158.66.206、3.77.61.29、63.177.180.213、63.179.20.23）未挂载 → 每个约 $3.6/月，建议释放。
- **1 台 stopped 的旧 dev**（`i-0c70127b8fa8bfb54`）仍占 EBS 费；确认无用后连快照清理。

---

## 七、基础设施即代码（Terraform）

- 状态在 `s3://devteam-css-terraform-state/css/terraform.tfstate`（tf 1.10.5）。
- **只纳管 staging 一台**（1×VPC/subnet、2×SG、1×EC2、1×EIP），**dev/preprod 是手工创建、无 IaC 覆盖** → 配置漂移、不可复现、安全组失管（见第三节）。

---

## 八、结论

客户 AWS 是"EC2 单机 + 全容器"自托管，**最突出的问题是安全组几乎全开**（pgadmin/kafka-ui/DB 端口对全网）、**S3 未阻断公开**（发票/PII 可公开读）、**IAM 与密钥管理薄弱**、**IaC 只覆盖 staging**。优先级：先收敛安全组 8006/8005/7432/22 → 开 S3 Public Access Block → 轮换密钥 → Terraform 纳管全部实例与安全组。
