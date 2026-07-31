# prod 环境

> VPC：css-prod（10.10.0.0/16）· 分支：`main` · 半自动部署（GitHub Environment 人工审批）
> 总拓扑与账号约束见 [README.md](README.md)；安全硬化逐条对照见 [../生产部署/01-独立服务器方案.md](../生产部署/01-独立服务器方案.md) §5。

## 定位

生产环境。uat 验收通过的代码 `merge uat → push main` 后，流水线自动构建镜像，**部署停在审批卡点**，人工在 GitHub 上点 Approve 才继续。基础设施与非生产完全隔离（独立 VPC + 独立 RDS）。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 c5.xlarge 起（可先 c5.large 观察负载），**私有子网，无公网 IP**（⏳ `enable_prod_compute` 门控待建） |
| 对外入口 | **ALB `css-prod`**（公有子网，80/443 对全网）→ prod 应用机:80；上域名 + ACM 后启用 HTTPS（域名在 GoDaddy，**不用 Route53**，ACM 走手动 CNAME 验证）（⏳ 门控待建） |
| 出网 | NAT 网关（托管，可靠性优先）（⏳ 门控待建） |
| 堡垒机 | ✅ **已建在跑**：`css-prod-bastion` = `i-0a6d6754c61c239d0`，t4g.micro + EIP `34.225.237.45`，22 ← 仅白名单 IP；唯一 SSH 入口，常驻运行 |
| 运行内容 | 三栈 compose：`css-prod-{infra,backend,frontend}`（kafka-ui/pgadmin 默认不启） |
| 数据库 | **独立 RDS `css-prod`**（PostgreSQL，Multi-AZ + 自动备份 ≥7 天 + 存储加密 + 删除保护），库 **`css-prod-main`** + **`css-prod-ocr`**（vector 扩展） |
| 镜像 | tag `prod-vN`（不可变版本号，N=Actions run 序号，回滚依据）+ `prod`（浮动）；手动推送 `prod-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/prod/*`；**密钥全新生成，绝不复制 test/preprod**（`PASSWORD_SALT` 除外——若迁移存量用户必须沿用原 salt，否则全员密码失效） |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/prod/*`；标签 **`Environment=css-prod`**（旧 `CssEnv` 已废除） |
| 硬化基线 | `DEBUG=0`/`SQL_ECHO=0`；S3 桶 Block Public Access 全开 + 预签名；RabbitMQ 禁 guest；容器 mem_limit/cpus；CloudWatch 告警（详见 01-方案一 §5 对照表） |

## 访问方式

| 目的 | 方式 |
|------|------|
| 用户访问产品 | ALB DNS / 域名（80/443 公开） |
| SSH 上服务器 | `ssh -J <prod堡垒机> <prod私网IP>`（仅你的 IP 能到堡垒机） |
| 连数据库 | 经堡垒机隧道 psql；无任何公网暴露 |

## 部署方式（CI/CD，2026-07-31 现状）

1. `git checkout main && git merge uat && git push neworg main`；
2. 流水线自动：lint → 测试 → build → push ECR（`prod-vN` + `prod`）——**main 分支 push 只构建，不部署**；
3. **部署 = 手动在 GitHub Actions 上 Run workflow**（Free plan 无 Required reviewers，手动触发即人工闸；GitHub Environment 名=分支名 `main`）；
4. 触发后：migrate job（**RDS 快照 → 核对 alembic_version → upgrade**）→ deploy job（SSM 按 tag `Environment=css-prod` 定位应用机）→ 健康检查冒烟；
5. 回滚：`workflow_dispatch` 选上一个 `prod-vN` tag 重新部署，分钟级。兜底：`docs/新aws账号/09-远程执行与手动部署/deploy-env.sh prod`。

## 现状（2026-07-31）

基础设施由 **css-terraform** 纳管：免费骨架（VPC/SG/IAM/S3/ECR/SSM 壳）与堡垒机 `css-prod-bastion`（`i-0a6d6754c61c239d0`，EIP `34.225.237.45`）✅ 已建在跑；应用机/RDS/ALB/托管 NAT 由 `enable_prod_compute` 门控，待 Paid plan 后开启（资源清单见 css-terraform `CLAUDE.md` 与 [aws-css-prod.md](aws-css-prod.md)）。prod 数据迁移属后续独立任务，工具在 `docs/老aws账号/`。依赖：Paid plan 升级 → 开门控建计费大件 → Parameter Store 填值（全新密钥）→ 域名/ACM（可后补，先用 ALB DNS + HTTP）。
