# CSS 环境总览（test / uat / prod）

> 本文件夹是 **CSS 三环境的权威文档**：拓扑、访问方式、部署方式、实施状态。
> 编制：2026-07-28。AWS 账号 `582797602427`（us-east-1，新账号）；与老账号 `021213872872` 的环境无关。
> CI/CD 完整方案见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md)；prod 安全硬化对照见 [../生产部署/01-独立服务器方案.md](../生产部署/01-独立服务器方案.md)。

## 文档索引

| 类别 | 文档 | 说明 |
|------|------|------|
| 环境 | [test.md](test.md) / [uat.md](uat.md) / [prod.md](prod.md) | 每环境：形态、访问、部署、现状 |
| AWS 群组 | [aws-css-non-prod.md](aws-css-non-prod.md) / [aws-css-prod.md](aws-css-prod.md) | 两个 VPC 群组：网络/服务器/RDS/SG/IAM 清单（资源 ID 随创建回填） |
| 服务技术 | [服务技术文档.md](服务技术文档.md) | 三栈架构、服务清单、配置注入模型、已知坑 |
| 价格 | [成本价格表.md](成本价格表.md) | 两群组成本明细 + 饼图 + 优化空间 |
| 脚本说明 | [../aws账号脚本说明.md](../aws账号脚本说明.md) | [docs/新aws账号/](../新aws账号/README.md)（新账号资源脚本）与 [docs/老aws账号/](../老aws账号/README.md)（老账号数据迁移）使用指南 |
| CI/CD 手册 | [../新aws账号/README.md](../新aws账号/README.md)（总流程）+ [08](../新aws账号/08-github-actions推镜像/README.md)/[09](../新aws账号/09-ssm-run-command/README.md) | GitHub Actions 与 SSM/deploy.sh 手册已并入对应脚本文件夹 |
| **配置值速查** | [配置速查.md](配置速查.md) | 手册/脚本要填的全部具体值：ARN、registry、标签、实例、参数路径、端口 |
| CI/CD | [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md) / [cicd-操作手册.md](cicd-操作手册.md) | 方案（v2.2）与日常操作 |

| 环境 | Git 分支 | VPC | 状态 |
|------|----------|-----|------|
| test | `test` | css-non-prod | 数据库已就位（css-non-prod 已载入 preprod 数据）；旧默认 VPC test 机已删，待建新 VPC 应用机 |
| uat | `uat` | css-non-prod | 待建 |
| prod | `main` | css-prod | 待建 |

## 总拓扑（2026-07-28 拍板：全私有子网 + 堡垒机唯一管理入口）

```
                         你的开发 IP 221.214.0.190（唯一管理白名单）
                                   │ SSH/HTTP
        ┌──────────────────────────┼──────────────────────────────┐
        ▼                          ▼                              ▼（公网用户）
┌─ VPC css-non-prod (10.20.0.0/16) ─────────┐   ┌─ VPC css-prod (10.10.0.0/16) ──────────┐
│ 公有子网×2                                 │   │ 公有子网×2                              │
│   网关机 css-nonprod-gw t4g.micro          │   │   ALB（产品对外 80/443）                 │
│   + EIP 3.225.148.166（✅ 已建）            │   │                                        │
│   （堡垒 22 ┃ NAT 出网 ┃ 反代 80→test,     │   │   NAT 网关                              │
│     8080→uat）                             │   │   堡垒机 t4g.nano + EIP（22）            │
│ 私有子网×2                                 │   │ 私有子网×2                              │
│   EC2 test（t3.large，test 三栈）          │   │   EC2 prod（c5.xlarge 起，prod 三栈）    │
│   EC2 uat （t3.large，uat 三栈）           │   │   RDS css-prod（PG，Multi-AZ）          │
│   RDS css-non-prod（PG16 单实例，✅ 已建）   │   │     css-prod-main / css-prod-ocr       │
│     css-test-main/-ocr、css-uat-main/-ocr  │   │                                        │
└────────────────────────────────────────────┘   └────────────────────────────────────────┘
   每 VPC：S3 Gateway Endpoint（免费）；CI/CD 经 SSM Run Command 直达私网应用机，不经堡垒机
```

**关键规则**：
- 应用服务器/RDS 全部私有子网、无公网 IP；管理访问只能经堡垒机（22/80/8080 仅放行 `221.214.0.190/32`）；
- 两个 RDS：prod 独立实例，非生产一个实例装 test+uat 四个库；**库名规范**：`css-<env>-main` / `css-<env>-ocr`。非生产实例 **`css-non-prod` 已在新 VPC 建成**（PG16.14，test 两库已载入 preprod 数据，旧默认 VPC 同名实例已删）；`css-prod` 实例被 Free plan 拦截，等升级 Paid plan；
- 资源创建脚本按账号分两个文件夹：`docs/新aws账号/`（01-vpc ~ 11-parameter-store 共 11 个维度脚本）与 `docs/老aws账号/`（数据迁移工具）；
- ECR 仓库**每环境独立**（`<env>/css-xxx`，3×7=21 个，lifecycle 每仓库保留最近 5 个镜像），镜像 tag `<env>-vN`（不可变版本号，N=GitHub Actions run 序号，每次发布自增，如 `test-v12`，回滚依据）+ `<env>`（浮动）；手动推送用 `<env>-manual-<sha7>`；
- 环境变量唯一事实源：SSM Parameter Store `/css/<env>/{backend,frontend}.env`；
- **三环境 AWS 凭证完全隔离**：每环境独立的 OIDC 部署角色、EC2 实例角色、应用 S3 用户（key 绝不跨环境复用，权限只够本环境），见 03-CICD §4.5；
- `.idea` 等 IDE 文件禁止上传 git。

**网络访问规范（2026-07-28 拍板，三条铁律）**：
1. **SSH 只能经堡垒机**：所有 EC2 的 SSH 一律走堡垒机跳板——nonprod=`css-nonprod-gw`（EIP `3.225.148.166`）、prod=`css-prod-bastion`；堡垒机仅放行管理 IP `221.214.0.190/32`；
2. **系统 Web 访问只能通过 ALB 配置的域名**：nonprod 已建 ALB 安全组 `css-nonprod-alb-sg`=`sg-0c8f420e1e46b5b4b`（ALB 脚本在 `docs/新aws账号/12-alb/`，等应用机+域名就绪后创建）；网关机 nginx 80/8080 反代是**过渡通道**，ALB 就绪后收掉；
3. **RDS 只能内网访问**：`--no-publicly-accessible`，安全组仅放行 app / 网关 SG。

## 成本与账号计划

月成本粗估：非生产 **~$156**、生产 **~$358**（明细见各环境文档）。

> ⚠️ **账号当前是 FREE plan，剩余 credits $53.87（2027-01-03 到期）**——创建 EC2/RDS/NAT/ALB 前**必须先升级 Paid plan**（控制台 Billing → 升级，账号所有者操作）。VPC/SG/IAM 等零成本资源不受限。

## 实施状态看板（随进度更新）

| 步骤 | 状态 |
|------|------|
| 方案文档（本文件夹 + 03-CICD v2.2） | ✅ 2026-07-28 |
| 两代码仓库 .idea 清理并推送新组织（三分支） | ✅ 2026-07-28 |
| VPC×2 网络骨架 + SG + IAM/OIDC + S3 端点（零成本） | ✅ 2026-07-28 |
| ECR 每环境独立 21 仓库（<env>/css-xxx）+ lifecycle 保留 5 | ✅ 2026-07-28 |
| docs/新aws账号/ 工具集（01-vpc ~ 11-parameter-store） | ✅ 2026-07-28 |
| **升级 Paid plan** | ⏳ **等用户操作（css-prod RDS 创建被拦截）** |
| RDS css-non-prod（新 VPC，PG16.14）+ test 两库载入 preprod 数据 | ✅ 2026-07-28（旧默认 VPC 实例与旧 test 机已删） |
| 网关机 css-nonprod-gw（t4g.micro + EIP 3.225.148.166） | ✅ 2026-07-28 |
| EC2 应用机×3（06-ec2）+ prod 堡垒机 + NAT + ALB + RDS css-prod | ⏳ 应用机待建；css-prod RDS 阻塞于升级 |
| CI/CD workflows + deploy bundle 落两仓库 test 分支 | ✅ 2026-07-28（backend `01eff1f7` / frontend `128a871f`） |
| Parameter Store `/css/test/*` 灌入 | ✅ 2026-07-28 |
| GitHub 仓库变量 + Environments 配置（手册 §6） | ⏳ 等用户操作 |
| 端到端验证（test 全绿）→ CI 提交晋级 uat/main | 待做 |
