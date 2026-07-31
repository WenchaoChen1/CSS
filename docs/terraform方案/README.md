# CSS AWS 基础设施 Terraform 化方案（初步方案分析 + 优化版）

> 📜 **历史存档（2026-07-30 方案分析记录；2026-07-31 标注）**。本文是 Terraform 迁移**动手之前**的方案分析过程，
> 仅保留决策脉络，文中的资源 ID / 建议 / 命令**不要当现状执行**。现状与规范以下列为准：
> - 资源与用法 = 独立仓库 `css-terraform/`（`CLAUDE.md`、`使用说明/`、`运行命令.md`、`执行手册.md`）——迁移已完成，33 个 stack、plan 全零 diff；
> - 分工 = `docs/新aws账号/职责划分.md`；凭证与地址 = 工作区根 `运维访问速查.local.md`（gitignore）。
>
> **与本文结论不同的后续实况（择要，2026-07-31）**：
> - Tag 键名最终**改为 `EnvironmentGroup` / `Environment`**（本文"沿用 Group/CssEnv"的建议已被用户拍板推翻，旧键已彻底删除，SSM 部署与 IAM 条件均按 `Environment`）；
> - test/uat **SG 已按环境拆分**（css-test-app-sg / css-test-alb-sg / css-uat-app-sg / css-uat-alb-sg，旧共用 SG 已删）；
> - 网关机改名 **css-non-prod-bastion**（原 css-non-prod-gw，nginx 反代停用，仅堡垒 + NAT）；prod 堡垒机 css-prod-bastion 已建，prod 应用机/RDS/ALB/NAT 仍由 `enable_prod_compute` 门控；
> - test/uat 应用机 **2026-07-30 重建，实例 ID 已变**（KeyName=css-test/css-uat，根卷加密，私网 IP 不变）；
> - demo 环境**已删除、不建**；State 按用户要求细拆（最终 33 stack，非本文的 7 stack）；
> - RDS master 密码 Secrets Manager 自动轮换实为 **7 天**（本文写 90 天有误）；库低权账号 css_app_test / css_app_uat 已建并投用；
> - kafka-ui 只走开发入口 ALB（业务 ALB 的 :8085 已全部撤除）。

> 状态（写作当时）：**方案文档，未做任何 AWS 变更**。基于 2026-07-30 对 `docs/新aws账号/` 全部 15 个组件脚本、
> `docs/环境/` 实况文档、两仓库 CI/CD 的全量盘点（12 个并行 agent，三视角评审：架构/安全/成本）。
> 原始需求：用户初步方案（三环境组 + 每环境 8 个 State + 每环境独立堡垒机 + 密钥全进 SSM + 双 Tag）。

---

## 〇、结论速览：初步方案逐条判定

| # | 初步方案条目 | 判定 | 原因 |
|---|---|---|---|
| 1 | 三环境组 css-prod / css-non-prod / css-demo | ✅ 保留 | 与现状两 VPC 结构一致，demo 作为第三组的**逻辑分组**成立 |
| 2 | prod 独立 VPC + RDS | ✅ 保留 | 现状已如此（css-prod VPC 骨架已建，RDS/EC2 等 Paid plan） |
| 3 | test/uat 共享 VPC + RDS | ✅ 保留 | 现状已如此 |
| 4 | demo 独立 VPC + 独立 RDS | ⚠️ 建议改 | 独立 VPC+RDS ≈ **$130/月**；进 non-prod VPC 共享 RDS ≈ **$101/月**、按需启停 ≈ **$32/月固定**。见 §四决策表 |
| 5 | 每环境独立 EC2/ALB/ECR/IAM/SSM/部署/监控 | ✅ 保留 | 现状已全部按环境独立（ECR 21 仓库、IAM 三套角色、`/css/<env>/*`、每环境 ALB） |
| 6 | 每环境独立 Security Group | ⚠️ 可选 | 现状 test/uat 共用 app-sg/alb-sg；真要互访隔离应**拆 SG**（有效）而不是加堡垒机（无效），且 SG 拆分是 ForceNew 级变更需窗口 |
| 7 | **每环境独立堡垒机（4 台）** | ❌ 不建议 | 同一 VPC 内多台堡垒机**零隔离收益**（隔离边界是 SG/IAM 不是台数），多花 ~$21/月多两台要打补丁的机器。改为**每 VPC 一台** + SSM Session Manager |
| 8 | **每环境 8 个 State（4×8=32 个）** | ❌ 必须改 | 与共享资源拓扑根本冲突（VPC/RDS/网关机/SG 是 test+uat 共享的，一个资源只能进一个 state）；network↔bastion 双向依赖无法单向化；对 1-2 人团队是纯负担。改为**两层 7 个 stack**，见 §三 |
| 9 | Remote State 取 VPC ID/Subnet ID/SG ID | ✅ 保留 | 但依赖必须严格单向：shared → env，env stack 绝不声明共享资源本体 |
| 10 | **密钥全进 SSM Parameter Store** | ⚠️ 现状已是，但 TF 侧有红线 | 参数**值**绝不能被 TF import/管理（明文进 state）。TF 只管"壳"，值继续走 `put-params.sh`。见 §五 |
| 11 | Tag = EnvironmentGroup + Environment | ⚠️ 改键名 | 现有 `Group` + `CssEnv` 语义完全等同且是**控制面标签**（SSM 部署定位 + IAM SendCommand 条件都消费 `CssEnv`），换键名会断部署链路。**沿用 Group/CssEnv**，另加 `ManagedBy=terraform` |
| 12 | CI/CD 分环境（含 demo） | ✅ 保留 | 现状已是 OIDC + 三环境隔离角色；demo 是纯增量（for_each 加一个元素） |
| 13 | pem / IAM 按环境隔离 | ✅ 现状已达标（pem 甚至是"一机一钥"比按环境更细） | TF 侧姿势：key pair 只管公钥；有两处存量安全债要还，见 §五.3 |

**总体判断**：方案的大方向（迁 Terraform、环境组隔离、密钥集中 SSM、每环境资源独立）**合适且大部分就是现状的成文化**。
必须修正的是四点：① State 拆分轴从"按环境×按组件"改为"**按共享层×按环境**"；② 堡垒机从每环境一台收敛为**每 VPC 一台**；
③ SSM 参数**值**与一切私钥/AK 不进 Terraform；④ Tag 键名沿用现有 `Group`/`CssEnv`。
另外方案遗漏了 4 类已建资源（S3×5、CloudWatch 全家、Budgets、GitHub OIDC provider）和 3 个前置决策（demo 落位、Paid plan 时点、state backend 设计）。

---

## 一、现状盘点结论（Terraform 的起点是 import，不是新建）

新账号 582797602427 / us-east-1 存量 ≈ **150-200 个 Terraform 资源地址**，全部手工脚本创建。关键存量：

| 类别 | 资源（必须 import，不可重建） | 关键 ID |
|---|---|---|
| VPC | css-non-prod（10.20.0.0/16，全量建成）、css-prod（10.10.0.0/16，仅零成本骨架） | `vpc-014be109b904d6a07` / `vpc-0ecf70f71565ddcc8` |
| 子网/路由 | 每 VPC 公×2 私×2、公私路由表、IGW、S3 Gateway 端点 | ID 见 `docs/环境/配置速查.md`，缺的用 discover 脚本补 |
| SG | 非生产 4 个：gw / alb / app / rds（**GroupName 不可改，名字差一个字符 = destroy+create**） | `sg-0f449992d538ac3b4` / `sg-0c7b0b571d74b1f2f` / `sg-0d06e029924989ee3` / `sg-0197c0db4578107ef`；prod 4 个待实查 |
| EC2 | 网关机 css-non-prod-gw（堡垒+iptables NAT，**私网出网生命线**）、css-test-app（三栈在跑）、css-uat-app | `i-08b0ef319d08eae38` + 两台应用机 `i-0b3e73ed51811b69c` / `i-00c635f52140cf035`；EIP `3.225.148.166`（释放即拿不回） |
| Key pair | wenchao（个人钥）+ css-non-prod-gw / css-test / css-uat（一机一钥，私钥仅本机 ~/.ssh/*.pem） | 私钥 AWS 不可找回，**绝不 delete+recreate** |
| RDS | css-non-prod（PG16.14, db.t4g.micro, 私有子网, 含已脱敏业务数据）+ 子网组 | 密码 Secrets Manager 托管（`rds!` 前缀 secret，勿单独 import） |
| ALB | css-test / css-uat（+ 各自 TG、listener、IP 型 attachment） | DNS 随机后缀**已烤入前端镜像 VITE_***，重建 = 换 DNS = 断服 |
| ECR | 21 个仓库（3 环境 × 7）+ 21 份 lifecycle policy | 有镜像在被 compose 引用，重建即断部署 |
| S3 | css-{test,uat,prod,dev}-582797602427 + css-dbsync-582797602427（test 桶 102 个生产对象） | 桶名全球唯一，删了可能抢不回 |
| IAM | GitHub OIDC provider、css-deploy-{test,uat,prod}（**ARN 写死在两仓库 workflow**）、css-ec2-{test,uat,prod}+profile、css-gw-non-prod、css-app-{dev,test,uat,prod} | 角色名不可改；信任策略 8 条 sub（含 `@*` 新格式）**逐字保真** |
| SSM 参数 | `/css/test/backend.env`（Advanced 层，≈4.4KB 整份 env）、`/css/test/frontend.env` | **不 import、不声明**（值含全部密钥） |
| 监控 | 18 条告警 + 2 Dashboard + 2 SNS 主题（**零订阅者**）+ 日志组 /css/test、/css/uat | 按 alarm-name / log-group-name import |
| Budgets | css-daily-cost 日预算（是否已建需实查） | import ID `<account_id>:css-daily-cost` |

**绝不 import 的黑名单（已删除资源）**：默认 VPC `vpc-0f1a28d652c598172`、旧 SG×6（`sg-0cb64...`、`sg-0cfa6...`、`sg-035ac...`、`sg-0c8f4...`、`sg-095c2...`、`sg-08e01...`）、旧 test 机 `i-08e110b5a5425980d`、旧共享 ALB css-nonprod-alb、旧桶 css-test-storage-582797602427 / 纯名 css-uat。也**不要声明 `aws_default_vpc`**（会把已删的默认 VPC 建回来）。

**三个必须先实查再写代码的分歧点**（README 与脚本矛盾）：kafka-ui 的 :8085 监听器是否实存、css-daily-cost 预算是否已建、SNS 订阅状态。

**盘点发现的隐性契约**（TF 必须原样保真，动了就是事故）：
1. `CssEnv` 标签被 `ssm:SendCommand` IAM 条件 + `run.sh`/`deploy-env.sh` 实例定位双重消费——**共享资源必须是 `css-shared`**（网关机被打成 `css-test`，test 的部署命令会以 root 跑到网关机上）；
2. gw-sg 的"`-1` 全协议 ← 10.20.0.0/16"是 **NAT 回程规则**，收窄成 tcp = test/uat 立即断网（拉不了镜像、SSM 掉线）；
3. 私有路由表 0.0.0.0/0 → 网关机 **ENI**（自建 NAT），网关机 `source_dest_check=false`；
4. workflow 写死 css-deploy-* 角色 ARN、ECR registry、RDS 实例名、参数路径——**这些名字在 TF 里全部视为冻结**。

---

## 二、State 拆分：从"4 环境 × 8 State"改为"两层 7 Stack"

### 为什么原拆法不成立

1. **共享资源归属冲突（致命）**：VPC/子网/SG/网关机/RDS 实例/dbsync 桶是 test+uat 共享的。"每环境一个 network state"意味着两个 state 声明同一个 VPC——Terraform 一个资源只能进一个 state，双重 import 后任何一边 plan 出 replace 都可能毁掉另一边正在用的资源。
2. **network ↔ bastion 双向依赖**：私有路由表（network）的默认路由指向网关机 ENI（bastion），网关机又依赖 network 的子网/SG——拆开后 apply 顺序无法单向化。
3. **ALB 与 EC2 强耦合**：IP 型 TG attachment 指向应用机私网 IP，应用机重建换 IP 时 attachment 必须原子更新，拆两个 state 就要跨 state 协同。
4. **32+ 个 state 对 1-2 人团队是纯负担**：存量总共 150-200 个资源，拆 32 份平均每份不到 10 个；换一次实例类型要按序 apply 三个 state。收益（爆炸半径、并行）全部落空，成本（依赖链、漂移面）全额支付。
5. 从粗到细再拆容易（`terraform state mv`），从细到粗合并痛苦——**先粗后细**。

### 优化后的 Stack 布局（满足你的全部隔离诉求）

| Stack | Backend key | 内容 | 依赖 |
|---|---|---|---|
| `00-bootstrap` | （一次性脚本，不进 state） | tfstate 桶 + KMS CMK + css-terraform 执行角色 | 无 |
| `10-account-global` | `account-global/terraform.tfstate` | GitHub OIDC provider、css-deploy-\*/css-ec2-\* 角色+profile、css-app-\* 用户（**不管 key**）、ECR 21(→28) 仓库+lifecycle、Budgets、参数 CMK×2 | 00 |
| `20-shared-non-prod` | `shared-non-prod/terraform.tfstate` | non-prod VPC/子网/路由/IGW/端点、4 个 SG 本体+全部规则（收口唯一属主）、网关机+EIP+默认路由+css-gw-non-prod 角色（`prevent_destroy`）、RDS css-non-prod+子网组、dbsync/dev 桶 | 10 |
| `21-shared-prod` | `shared-prod/terraform.tfstate` | prod VPC 骨架（import）+ 堡垒机/托管 NAT/RDS（`enable_prod_compute` 变量门控） | 10 |
| `30-env-test` / `31-env-uat` / `33-env-demo` | `env-<env>/…` | 应用机、ALB+TG+attachment（**同 stack！**）、环境 S3 桶、monitoring（SNS+9 告警+Dashboard+日志组）、SSM 参数壳 | 20 |
| `32-env-prod` | `env-prod/…` | 同上，`enable_prod_compute` 门控 | 21 |

这个布局下你的隔离目标全部达成：**改 ALB 不碰 IAM/ECR**（ALB 在 env stack，IAM/ECR 在 account-global）；**改 test 不碰 uat**（各自 env stack）；**改非生产不碰生产**（不同 stack + 不同 shared 层）。唯一"合并"的是强耦合资源（ALB+EC2 同 stack、网关机+网络同 stack）——这恰恰是避免跨 state 事故的正确做法。

### 目录结构（原生 Terraform；不用 Terragrunt，不用 workspaces）

```
terraform/
├── modules/
│   ├── network/            # VPC+子网+路由+SG 本体与规则（规则一律用独立 aws_vpc_security_group_ingress_rule）
│   ├── gateway-host/       # non-prod 自建 NAT 网关机：instance+EIP+source_dest_check=false+aws_route 默认路由
│   ├── bastion-nat/        # prod：纯堡垒 + aws_nat_gateway（与 non-prod 结构不同，独立模块，勿套同一模板）
│   ├── rds/                # manage_master_user_password=true；engine_version 只钉 "16"
│   ├── app-instance/       # 应用机（ignore_changes=[ami,user_data,key_name]，pin 实际 AMI ID）
│   ├── alb-web/            # lb+listener+tg+attachment；idle_timeout=3600；certificate_arn 变量留 443 位
│   ├── monitoring/         # sns + 9 告警（维度用 arn_suffix 派生）+ dashboard + log group + logs 内联策略
│   ├── app-bucket/         # bucket+pab+sse+versioning+lifecycle+cors（CORS origins 做 per-env 变量，prod 收真实域名）
│   ├── ecr-env/            # for_each 7 仓库+lifecycle（JSON 与 ECR 规范化格式对齐，否则永久 diff）
│   ├── iam-env/            # deploy+ec2+app-user 三件套（信任策略 sub、策略模板用 locals 统一渲染）
│   └── params-env/         # SSM 参数壳（只管 name/type/tier/kms/tags）
├── stacks/
│   ├── 10-account-global/  # {backend.tf, providers.tf, main.tf, imports.tf, variables.tf}
│   ├── 20-shared-non-prod/
│   ├── 21-shared-prod/
│   └── 30-env-test/ 31-env-uat/ 32-env-prod/ 33-env-demo/
└── scripts/
    ├── 00-create-tf-backend.sh   # state 桶+CMK 自举（走脚本，符合现行"只走脚本"铁律，跑一次即退役）
    └── discover-ids.sh           # 生成 import 清单（补齐文档缺失的子网/RT/sgr/ALB ARN 等 ID）
```

**否决 Terragrunt**：7 个 stack 手写 backend/provider 的成本可忽略，Terragrunt 给 Windows 环境多加一个二进制、一层 HCL 方言，对 1-2 人团队是负资产（stack 数将来超 15 个再评估）。
**否决 workspaces**：test/uat 共底座、prod NAT 结构不同、Free plan 使 prod apply 必败——"同构环境只差变量"的假设全不成立；且 `workspace select` 选错环境是小团队高频事故。

### Backend（TF ≥ 1.11，S3 原生锁，免 DynamoDB）

```hcl
terraform {
  required_version = ">= 1.11"
  backend "s3" {
    bucket       = "css-tfstate-582797602427"   # 带账号后缀（纯名桶被占的教训）
    key          = "shared-non-prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true                          # S3 原生锁
    encrypt      = true
    kms_key_id   = "<css-tfstate CMK arn>"       # 专用 CMK，不用 aws/s3
  }
}
provider "aws" {
  region = "us-east-1"
  default_tags { tags = { Group = "css-non-prod", ManagedBy = "terraform" } }
}
locals { css_env = "css-shared" }   # env stack 里是 "css-test" 等；CssEnv 不进 default_tags！
```

state 桶：versioning + Public Access Block 全开 + bucket policy 只允许 TF 执行主体。
**TF 执行身份**：新建 `css-terraform` 角色（信任本账号 + MFA 条件），权限从 Admin 收敛到迁移涉及的服务面；现在的 css-test Admin 用户降级为只能 AssumeRole；**css-deploy-\* CI 角色对 state 桶零权限**（部署角色读到 state = 读到全账号拓扑）。
providers 锁文件：`terraform providers lock -platform=windows_amd64 -platform=linux_amd64`（防将来 CI 跑 Linux 时 hash 不匹配）。
Windows 细节：`.gitattributes` 强制 `*.tf *.tfvars text eol=lf`；辅助脚本统一 `--output json` 解析（GBK 截断教训）；涉及 `/css/...` 路径沿用 `MSYS_NO_PATHCONV=1`。

### Tag 策略（回答你的"八、Tag 要求"）

你要的两个语义**沿用现有键名**：`EnvironmentGroup` → **`Group`**（css-non-prod / css-prod）、`Environment` → **`CssEnv`**（css-test / css-uat / css-prod / css-demo / **css-shared**）。原因：`CssEnv` 是控制面标签（IAM `ssm:resourceTag/CssEnv` 条件 + 部署脚本 `--filters` 定位目标机 + Cost Allocation），换键名 = 断部署链路 + 全量重打标签。

- `default_tags` 只放 `Group` + `ManagedBy=terraform`；
- `CssEnv` 逐资源显式声明：共享资源恒 `css-shared`（VPC/子网/SG/网关机/RDS/dbsync 桶），环境资源 `css-<env>`；
- 按"共享组×环境"拆 stack 后，每个 stack 内 CssEnv 恰好同值——这本身就是拆分正确性的试金石；
- 给 css-deploy-\* 保持**不含** `ec2:CreateTags`（标签即边界，能改标签就能绕过 SendCommand 条件）；可在 CI 加 plan JSON 检查：凡出现 CssEnv 值变更即 fail；
- 迁移完成后 `tag-all-resources.sh` 退役，标签由 TF 全权管理；双轨期 `Name` 标签值必须与现状**逐字一致**（它是脚本的查询键），禁止"顺手规范化"。

---

## 三、Import 策略（每个 stack 的验收门禁 = `terraform plan` 零变更）

用 **TF ≥ 1.7 的 import blocks**（可 for_each、进 PR 可审查、可重放），配合 `terraform plan -generate-config-out=generated.tf` 生成初稿再收编进模块。21 个 ECR 仓库一个块搞定：

```hcl
locals {
  envs  = ["test", "uat", "prod"]        # 加 demo 只改这里（21 → 28 仓库）
  repos = ["css-backend/app", "css-backend/nginx", "css-backend/sms-sender",
           "css-backend/email-sender", "css-backend/ai-assistant",
           "css-backend/catalog-ocr", "css-frontend/app"]
  ecr_names = { for p in setproduct(local.envs, local.repos) : "${p[0]}/${p[1]}" => { env = p[0] } }
}
import {
  for_each = local.ecr_names
  to       = aws_ecr_repository.this[each.key]
  id       = each.key                    # import ID 即仓库名，如 test/css-backend/app
}
```

**已知的 import 高难点与对策**：

| 资源 | 坑 | 对策 |
|---|---|---|
| EC2 实例 ×3 | `user_data`/`ami` 漂移（脚本每次取 latest AL2023）；test/uat 应用机 `key_name` 元数据仍是 `wenchao` | pin 实际 AMI ID + `lifecycle ignore_changes=[ami,user_data,key_name]`；网关机另加 `prevent_destroy` + `source_dest_check=false` |
| SG 规则 | inline 规则与独立资源混用会互相清除 | 全部改独立 `aws_vpc_security_group_ingress_rule`（有 `sgr-` ID 可 import，先 describe 逐条取 ID）；SG 本体+规则唯一属主 = shared stack |
| aws_route | import ID 格式特殊 | `rtb-xxx_0.0.0.0/0` |
| IAM | inline policy ID = `role:policy-name`；attachment = `role/policy-arn`；信任策略 `@*` 通配 sub 一个字符不能少 | locals 显式列全 8 条 sub 并加注释；import 后第一次 plan 必须零 diff；三个 deploy 角色加 `prevent_destroy` |
| key pair | import 后 `public_key` 读不回，必有 diff | 公钥从本地 .pem 派生：`ssh-keygen -y -f ~/.ssh/css-test.pem`，写进 config 再 import |
| ALB/TG | `idle_timeout=3600`、`deregistration_delay=30`、`matcher 200-399` 容易漏写 | import 后逐属性对齐到 plan 干净 |
| ECR lifecycle | ECR 规范化 JSON，文本不一致 = 永久 diff | 策略 JSON 按 ECR 规范化格式写 |
| S3 桶 ×5 | 每桶拆 6 个子资源（bucket/pab/sse/versioning/lifecycle/cors）分别 import；versioning 开了关不掉 | plan 出 `Suspended` 就是写错了 |
| SSM 参数 | **不 import**（值进 state）；Advanced 层不可降 Standard | 现存 /css/test/* 完全不声明；新环境只管壳 |
| CloudWatch Dashboard | body 是脚本拼的 JSON，jsonencode 重写必有格式 diff | 接受首次覆盖 |
| Budgets | DAILY 预算只支持 ACTUAL 通知；IncludeCredit=false 必须保留 | 写 FORECASTED 会直接报错 |

**顺序**：10-account-global（workflow 写死 ARN，最怕断）→ 20-shared-non-prod → 30-env-test（在跑业务的环境验证 plan 干净）→ 31-env-uat → 21/32-prod（骨架 import + 门控）→ 33-demo（纯绿地）。每个 stack 做不到 "No changes" 就不进下一个。

---

## 四、demo 环境落位（需要你拍板的决策表）

**账号/区域只有一个不折腾的答案：新账号 582797602427 / us-east-1**。整套体系对账号和区域硬编码耦合（脚本 REGION、workflow 的 registry+角色 ARN、OIDC 每账号一个、镜像在本账号 ECR）；老账号是正在迁出的客户遗留环境，放 demo 是逆着迁移方向走。

VPC/RDS 落位按成本决策（裸奔价口径，参考 `docs/环境/成本价格表.md`）：

| 方案 | 内容 | 月成本 | 前置条件 |
|---|---|---|---|
| A（你的原方案） | 独立 VPC + 独立 RDS + 独立网关机 + ALB | **~$130** | 无 |
| B | non-prod VPC 新子网 + 独立 RDS micro | ~$120 | 无 |
| **C（推荐，demo 常驻）** | non-prod VPC（新子网 10.20.12/13.0/24）+ **共享 RDS**（新库 css-demo-main/-ocr）+ 共享网关 NAT + 独立 ALB | **~$101** | RDS 先升 db.t4g.small（+$12，**需 Paid plan**；micro 实测仅剩 146MB 内存） |
| **D（推荐，仅演示用）** | = C 且应用机只在演示时开机 | **~$32 固定** + $0.095/h | 同 C |
| E | 分时顶掉 test 栈 | $0 | test 机 8GB 跑不下双栈、数据混用，**不推荐** |

Terraform 侧无论选哪个，demo 都是 non-prod 组下的第三个环境实例（`Group=css-non-prod`, `CssEnv=css-demo`），把"环境清单"做成 account-global/shared stack 的 `list(string)` 变量，**加 demo = 往 `["test","uat","prod"]` 里加一个词**（ECR 21→28、IAM 加 css-deploy-demo/css-ec2-demo/css-app-demo、参数路径 /css/demo/*、GitHub 侧加 demo 分支或 workflow_dispatch）。

**demo 安全基线**（写死进方案）：数据只允许从**已脱敏的 test 库**二次复制，永不直连 prod/preprod dump；`anonymize-db.sh` 白名单加 demo 并修 phone 脱敏非幂等 bug；demo 用**独立 PASSWORD_SALT + 独立演示口令**（不沿用 test 库的统一脱敏口令——否则任何演示观众可登入全部 188 个账号），演示账号白名单化；demo 桶 CORS 不复制 `AllowedOrigins=["*"]`。

**成本时间线（决策锚点）**：credits 余 $53.87、当前烧 $3.4/天 → **约 2026-08 中旬烧完**，之后账单跳向裸奔价。现状不动 ~$235/月；+demo（C）~$335/月；prod 全套 + demo ~$700/月；Paid plan 后买预留实例/Savings Plan 可降 30-40%（$593→$360-410）。**"demo 建多大"和"何时升 Paid plan"是同一个决策**：Paid plan 同时解锁 prod RDS/EC2、RDS 升 small（demo 共享 RDS 的前置）、预留实例。

---

## 五、安全红线（一票否决项）与密钥/pem 隔离

### 1. TF 代码里出现以下任意一项即 review 打回

| 禁止 | 原因 | 正确姿势 |
|---|---|---|
| `tls_private_key` | 私钥明文进 state | 本地生成/已有 .pem 派生公钥，`aws_key_pair` 只管 `public_key` |
| `aws_iam_access_key` | secret 进 state | key 生命周期永久排除在 TF 外，保留 `create-app-s3-user.sh --new-key` 带外流程 |
| `aws_db_instance.password` | 明文进 state + 触发密码重置 | `manage_master_user_password = true`（对齐现状，`rds!` secret 由 RDS 托管，勿单独 import） |
| `aws_ssm_parameter` 带真实 value，或 **import 现存 `/css/test/*`** | import 会把整份 env（DB 口令/JWT_SECRET/SALT/S3 AK）明文拉进 state；参数 History 还永久保留旧值 | 现存两个参数**不 import 不声明**；新环境（uat/prod/demo）只管壳：占位 value + `lifecycle { ignore_changes = [value] }`，值走 `put-params.sh`。轮换密钥后"删参数重建"（TF replace 壳）恰是清 History 的合法手段 |

```hcl
resource "aws_ssm_parameter" "backend_env" {
  name   = "/css/${var.env}/backend.env"
  type   = "SecureString"
  tier   = "Advanced"                       # 不可降级，import/声明时必须对齐
  key_id = aws_kms_key.params.arn           # per-组 CMK，见下
  value  = "PLACEHOLDER-managed-by-put-params"
  lifecycle { ignore_changes = [value] }
}
```

### 2. IAM 隔离：现状已达标，import 保真 + 四处增强

现状 GitHub Actions 是**纯 OIDC 按环境分角色**（无任何长期 AWS 密钥）、ECR push 限 `<env>/*`、SendCommand 按 CssEnv 条件、参数按路径收口——**TF 的任务是逐字保真地 import，不是重造**。增强项（都会产生 plan diff，选部署间隙做）：

1. **ECR pull 收窄**：css-ec2-\* 现挂托管策略 `AmazonEC2ContainerRegistryReadOnly`（Resource=\*，test 机可拉 prod 镜像），换成按 `<env>/*` 收窄的内联策略，与 push 策略同一个 locals 模板渲染；
2. **参数 KMS 两层隔离**：建 2 把 CMK（css-params-non-prod / css-params-prod，$1/月/把），SecureString 指定 key_id，各角色 `kms:Decrypt` 限本组 key——IAM 路径条件写错时还有 KMS 兜底；
3. css-deploy-\* 显式不含 `ec2:CreateTags/DeleteTags`；
4. 遗留清理：`css-non-prod-ec2-role` 直接删除不 import；`setup-ssm.sh` 历史分支可能给旧角色挂过 `css-<env>-params-transition` 内联策略，迁移前 `list-role-policies` 实查。

### 3. pem 隔离：现状"一机一钥"已比"按环境"更细，两处存量债要还

- **TF 姿势**：`aws_key_pair` 只声明 public_key（`ssh-keygen -y -f ~/.ssh/css-test.pem` 派生），import 现有 4 把；`key_name` 逐字对齐（改名=ForceNew=作废本地私钥）；authorized_keys 属机内配置，保留 `create-instance-keys.sh` 作 TF 外运维脚本；
- **债 ①（已处理 2026-07-30）**：个人钥 wenchao 的 passphrase 曾明文写进 `docs/新aws账号/06-ec2/README.md` 与 `docs/环境/本地连接数据库.md`——私钥本体未入库，风险有限，已从两份文档中删除口令（用户拍板：不轮换密钥）；
- **债 ②**：个人钥写进了全部三台机的 authorized_keys，是跨环境通杀通道，与"按环境隔离"矛盾——降级为 break-glass 应急通道，日常登录/端口转发迁 **SSM Session Manager**（三台机 SSM 已 Online、零新建资源，Session 日志落 CloudWatch）。

### 4. 数据库层隔离（TF 之外的配套硬任务，同窗口做）

test/uat 应用现在**共用 RDS master 账号**连库（master 密码内嵌 backend.env 三处）：test 环境的任何人可对 uat 库为所欲为，且 Secrets Manager 自动轮换（实为 7 天，非当时文档所写的 90 天）一触发参数里的旧密码即失效、应用全挂。配套动作：新增 `05-数据同步/create-app-db-users.sh`（经网关机 SSM 执行）建 `css_app_test` / `css_app_uat`（将来 `css_app_demo`）低权角色，各自只 GRANT 本环境两库 + REVOKE CONNECT 对方库；backend.env 换低权账号后重跑 put-params。此后 master 轮换只影响运维通道。库级对象（建库/pgvector/低权账号）**不进 TF**（postgresql provider 无网络路径），保留脚本。

### 5. 堡垒机（回答你的"五、堡垒机要求"）

**不要按环境加堡垒机**。test/uat 同 VPC 共用一个 app-sg，上了网关机就同时可达两台应用机——同 VPC 再放两台堡垒机隔离度为零，只多 ~$21/月和两台要打补丁的机器。收敛为**每 VPC 一台**：non-prod 保留 css-non-prod-gw（兼自建 NAT，$10/月 vs 托管 NAT $33/月是刻意省钱）、prod 上线时建 css-prod-bastion + 托管 NAT（跨 VPC 才有真隔离价值，托管 NAT 换掉单点是花在生产稳定性上的钱）。堡垒机建模在 **shared 层**不是 env 层。若确要 test/uat 互访隔离：拆 app-sg 为 css-test-app-sg / css-uat-app-sg（ForceNew 级变更，参考 `rename-security-groups.sh` 的双挂零中断流程安排窗口）——这才是有效手段。

---

## 六、Free plan 门控与 CI/CD 边界

### Free plan（拦截发生在 apply 期，plan 全绿也会炸）

已实测被拦截：RDS 非 micro 规格（prod t4g.medium/Multi-AZ、non-prod 升 small）、prod 应用机、t4g.nano。若混在无门控的 stack 里，apply 半途失败会留下半套资源（托管 NAT 若先建成即空烧 $33/月）。对策：

```hcl
variable "enable_prod_compute" { default = false }   # Paid plan 当天翻 true
# prod 的 RDS/EC2/堡垒/NAT Gateway/私有默认路由全部 count/for_each 挂在它上面
```

现在就能安全 apply：全部存量 import + demo 全套绿地（m7i-flex.large 和 db.t4g.micro 实测可建）+ prod VPC 骨架 import。必须等 Paid plan：prod RDS/应用机/堡垒/托管 NAT、RDS 升 small。

### CI/CD 与 Terraform 的边界（成文）

**永不进 TF 的三类**：部署动作（镜像构建推送、SSM Run Command 部署链路、deploy.sh）、数据操作（restore/sync/anonymize——塞 null_resource 会把 DSN/密码带进 state）、密钥值（参数值、AK/SK、私钥、authorized_keys）。`push-ecr.sh`、`run.sh`、`deploy-env.sh`、`put-params.sh`、`setup-autodeploy.sh`、05-数据同步全套保留为 day-2 工具。

**反向依赖要管起来**：workflow/脚本写死的角色 ARN、registry、桶名、实例名、参数路径——TF 里这些名字全部冻结；可让 TF output（alb_dns、rds_endpoint、bucket 名）写入 SSM `/css/tf/<stack>/*`，脚本改为读它而不是各自硬编码（顺带解开 env stack 对 shared state 文件的直接读权限）。

**10-自动重新部署** 是机器内 systemd/cron 文件，TF 重建 EC2 后会丢——并入 user_data/cloud-init 或明确记录为建机后手工步骤。

### ALB（短期接受 4 个，设复盘点）

每 ALB 固定 ~$27/月（含节点 IPv4），4 个 ~$108/月。共享 ALB 按 Host 路由现在**做不到**：没有域名和 ACM，用户直接访问 ALB 随机 DNS 且被烤进前端镜像。把"**买域名 + ACM + 443 监听器**"列为 prod 上线硬前置（`alb-web` 模块留 certificate_arn 变量）；域名就位后复盘 test/uat/demo 是否合并共享 ALB（省 ~$54/月，代价是前端镜像改用域名重建）。

---

## 七、迁移路线图（1-2 人团队现实排期）

| 期 | 内容 | 工作量 | 收益/验收 |
|---|---|---|---|
| **P0** | `00-create-tf-backend.sh` 建 state 桶+CMK+css-terraform 角色（走脚本，符合现行铁律）；pin TF ≥1.11；`discover-ids.sh` 补齐缺失 ID + 实查三处分歧 | 0.5-1 天 | 前置 |
| **P1** | `10-account-global` + `20-shared-non-prod` import（IAM/OIDC/ECR/网络/SG/网关机/RDS） | 2-3 天 | **最大**：SG ForceNew、OIDC 信任策略漂移是最危险区，import 后立即获得 drift 检测。验收 = plan 零变更 |
| **P2** | `30-env-test` + `31-env-uat` import（应用机/ALB/S3/监控/参数壳） | 2-3 天 | drift 检测覆盖全资源面；验收同上 |
| **P3** | `21-shared-prod` + `32-env-prod`（骨架 import + `enable_prod_compute=false` 门控，plan-ready） | 1 天 | prod 就绪，Paid plan 当天翻开关 |
| **P4** | `33-env-demo` 绿地 apply（**第一个纯模块新建的环境，半天见效**；有 deadline 可提前与 P2 并行） | 1 天 | 验证模块复用性 + 本次迁移唯一"新产出" |
| **P5** | 配套硬任务：DB 低权账号、ECR pull 收窄、参数 CMK、SSM Session Manager 常态化、wenchao 钥轮换（这条其实应立即做） | 1-2 天 | 安全增强落地 |

**每期结束跑全量 plan 确认零 diff 再进下期。**

### 双轨期纪律与"铁律"改写

- TF 接管一个组件的**当天**，在对应 `docs/新aws账号/<NN>/README.md` 顶部标注"已由 Terraform stack `<名>` 接管，本目录创建类脚本废弃/只读"，并维护一张**脚本 → stack 的 cutover 对照表**——这就是现行"AWS 变更只走脚本"铁律的正式改写载体（新铁律：**资源创建/变更走 Terraform，部署/数据/密钥值操作走保留脚本**）；
- 双轨期严禁再跑 create-\*.sh（幂等脚本的 `|| true` 会绕过 state 直接改线上造成 drift）；
- 立即可做的三件零成本事（不等 TF）：① 轮换 wenchao 密钥/passphrase 并清理两份文档；② 给 SNS 主题和 Budgets 补订阅邮箱（现在告警发不出去）；③ 实查三处文档分歧。

---

## 八、遗留决策清单（需要你拍板）

| # | 决策 | 选项 | 推荐 |
|---|---|---|---|
| 1 | demo 落位 | §四 A/B/C/D/E | **C**（常驻）或 **D**（仅演示时开机）；若短期不升 Paid plan 则只能 B 变体（独立 micro RDS，~$116-120） |
| 2 | Paid plan 升级时点 | 现在 / prod 上线前 / demo 上线前 | credits 约 8 月中旬烧完 + demo 共享 RDS 前置 + prod 全被拦 → **建议与 demo/prod 里程碑绑定，尽早** |
| 3 | 域名 + ACM | 现在买 / prod 前买 | **prod 硬前置**；买了以后再复盘 ALB 合并 |
| 4 | test/uat SG 互访隔离 | 拆 app-sg / 维持共用 | 非必须；要做就拆 SG（双挂零中断流程），不是加堡垒机 |
| 5 | TF 代码仓库位置 | 工作区新 `terraform/` 目录（随本 docs 仓库）/ 独立仓库 | 建议独立仓库或本仓库根 `terraform/`（state 无密钥后风险可控，但 repo 现为私有是前提） |
