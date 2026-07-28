# prod 环境

> VPC：css-prod（10.10.0.0/16）· 分支：`main` · 半自动部署（GitHub Environment 人工审批）
> 总拓扑与账号约束见 [README.md](README.md)；安全硬化逐条对照见 [../生产部署/01-独立服务器方案.md](../生产部署/01-独立服务器方案.md) §5。

## 定位

生产环境。uat 验收通过的代码 `merge uat → push main` 后，流水线自动构建镜像，**部署停在审批卡点**，人工在 GitHub 上点 Approve 才继续。基础设施与非生产完全隔离（独立 VPC + 独立 RDS）。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 c5.xlarge 起（可先 c5.large 观察负载），**私有子网，无公网 IP** |
| 对外入口 | **ALB**（公有子网，80/443 对全网）→ prod 应用机:80；上域名 + ACM 证书后启用 HTTPS |
| 出网 | NAT 网关（托管，可靠性优先） |
| 堡垒机 | t4g.nano + EIP，22 ← 仅 `221.214.0.190/32`；唯一 SSH 入口 |
| 运行内容 | 三栈 compose：`css-prod-{infra,backend,frontend}`（kafka-ui/pgadmin 默认不启） |
| 数据库 | **独立 RDS `css-prod`**（PostgreSQL，Multi-AZ + 自动备份 ≥7 天 + 存储加密 + 删除保护），库 **`css-prod-main`** + **`css-prod-ocr`**（vector 扩展） |
| 镜像 | tag `prod-vN`（不可变版本号，N=Actions run 序号，回滚依据）+ `prod`（浮动）；手动推送 `prod-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/prod/*`；**密钥全新生成，绝不复制 test/preprod**（`PASSWORD_SALT` 除外——若迁移存量用户必须沿用原 salt，否则全员密码失效） |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/prod/*`；标签 `CssEnv=css-prod` |
| 硬化基线 | `DEBUG=0`/`SQL_ECHO=0`；S3 桶 Block Public Access 全开 + 预签名；RabbitMQ 禁 guest；容器 mem_limit/cpus；CloudWatch 告警（详见 01-方案一 §5 对照表） |

## 访问方式

| 目的 | 方式 |
|------|------|
| 用户访问产品 | ALB DNS / 域名（80/443 公开） |
| SSH 上服务器 | `ssh -J <prod堡垒机> <prod私网IP>`（仅你的 IP 能到堡垒机） |
| 连数据库 | 经堡垒机隧道 psql；无任何公网暴露 |

## 部署方式（CI/CD）

> ⚠️ **现状（2026-07-28）**：CI 只推镜像（migrate/deploy job 已在 workflow 注释）；部署 = 手动执行 `docs/新aws账号/09-ssm-run-command/deploy-env.sh prod`。以下为恢复注释后的目标态。

1. `git checkout main && git merge uat && git push neworg main`；
2. 流水线自动：lint → 测试 → build → push ECR（`prod-vN`）；
3. **停在 deploy job**：GitHub Environment `production`（Required reviewers）等你审批；
4. 审批后：migrate job（**RDS 快照 → 核对 alembic_version → upgrade**）→ deploy job（SSM → prod 应用机）→ 健康检查冒烟；
5. 回滚：`workflow_dispatch` 选上一个 `prod-vN` tag 重新部署，分钟级。

## 现状（2026-07-28）

网络/SG/IAM 骨架已建（见 aws-css-prod.md，资源 ID 已回填），计费资源（EC2/RDS/NAT/ALB）待 Paid plan 升级后创建（本任务与老账号环境无关，prod 数据迁移属后续独立任务，工具在 `docs/老aws账号/`）。依赖：Paid plan 升级 → css-prod VPC 全套 → Parameter Store 填值（全新密钥）→ 域名/ACM（可后补，先用 ALB DNS + HTTP）。
