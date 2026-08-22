# CI/CD 方案：GitHub Actions × 新组织仓库（v2.2）

> 📜（2026-08-03 补注：文中"CI 只推镜像/deploy job 已注释"为当时状态——**自动部署已于 2026-07-28 晚恢复**，现状见 docs/cicd-操作手册.md。）
> 📜 **历史存档（2026-07-31 标注）**：本文是 CI/CD 设计与拍板记录（v2.2，2026-07-28）。CI/CD 主体已按此落地且仍有效（push test/uat 自动构建+migrate+SSM 部署；main 只构建、prod 手动 Run workflow），但文中**基础设施细节多处已过时**，现状以 css-terraform（33 stack，`css-terraform/使用说明/`）与 [../新aws账号/README.md](../新aws账号/README.md) 为准。已知变化：① 标签键 `CssEnv`/`Group` 已彻底废除，改为 `Environment`/`EnvironmentGroup`（SSM 部署与 IAM 条件均按 `Environment` 定位）；② 网关机已改名 **css-non-prod-bastion**（nginx 反代早已停用；kafka-ui 只走开发入口 ALB `css-non-prod-entry`，业务 ALB 8085 已撤）；③ test/uat 应用机 2026-07-30 重建，实例 ID 已变；④ uat 库已建成（css-uat-main/css-uat-ocr，=test 数据）；⑤ prod 堡垒机 css-prod-bastion 已建，应用机/RDS/ALB/NAT 仍等 Paid plan（`enable_prod_compute` 门控）；⑥ `css-deploy-*` OIDC 角色已收编进 css-terraform 的 css-github stack（角色名/ARN 未变）；⑦ 旧共用 SG 已拆为每环境独立 app-sg/alb-sg。具体 ID/地址一律见 css-terraform 与工作区根 `运维访问速查.local.md`。

> 📖 **配置与使用手册**（怎么配、怎么跑、出问题怎么查）已并入脚本文件夹：总流程见 [../新aws账号/README.md](../新aws账号/README.md)，[GitHub Actions → 08](../新aws账号/08-github-actions推镜像/README.md)，[SSM + EC2 deploy.sh → 09](../新aws账号/09-ssm-run-command/README.md)。本文是设计方案。

> **v2 更新（2026-07-28）**：v1（2026-07-23）编制时代码还在老账号、只针对生产。现在代码已迁入新组织 **Chain-Serve-Solutions**（`Chain-Service-Solutions-Backend` / `-Frontend`，分支模型 **main=prod、uat、test**），本版改为**覆盖 test / uat / prod 三环境的完整 CI/CD**，并给出**环境变量配置问题的系统解法**。
> **v2.1 补充（2026-07-28 用户拍板）**：目标基础设施定为**两套 VPC**（`css-prod` / `css-non-prod`，各配一台最便宜堡垒机）+ **两个 RDS**（prod 独立、非生产 test/uat 共用），见 §5.0；**编排文件进 Backend 仓库 `deploy/`，方案文档留在工作区 `docs/`（与代码仓库分离）**。
> **v2.2 补充（2026-07-28 二次拍板）**：**内部服务器全部私有子网、只能经堡垒机访问**；管理白名单 `221.214.0.190/32`；`.idea` 禁止上传；直接在新 AWS 账号创建资源（与老账号环境无关）；环境文档整理到 css 库 `docs/环境/`。⚠️ 账号 FREE plan 剩 $53.87 credits，计费资源须先升级 Paid plan（§5.0）。
> 事实基线：2026-07-28 实查 `部署包/`、`CSS_backend-main/deploy/`、两仓库测试与构建工具链。只出方案，确认后再落地。

---

## 1. 目标全景

每个环境一条**同构**流水线，形状与你的草图一致，环节做了三处强化（OIDC 免密钥、双 tag 可回滚、部署后验证）：

```
git push origin <test|uat|main>
        │
        ▼
GitHub Actions 自动触发（GitHub 托管 runner，不碰业务机）
        │
        ├── Lint + 编译检查        （后端 black/isort/flake8；前端 eslint + vite build）
        ├── 单元测试               （后端 pytest[全栈 compose]；前端 jest）
        ├── OIDC 换取 AWS 临时凭证  （无长期 AK/SK 存 GitHub）
        ├── Docker Build（buildx 缓存，--platform 固定）
        ├── Push 到 ECR            （双 tag：<env>-vN 不可变版本号 + <env> 浮动别名）
        │
        ▼  （prod 在此处有 Environment 人工审批卡点）
AWS SSM Run Command（免 SSH、不开 22、不管 pem）
        │
        ▼
EC2 自动执行 deploy.sh（增强版）
        │
        ├── 从 SSM Parameter Store 渲染 .env（环境变量方案 §4）
        ├── ECR 登录 + docker pull
        ├── docker compose up -d --wait（等健康检查通过）
        ├── Health Check 冒烟（curl /api/docs、前端 /、ocr-api）
        ├── 清理旧镜像（docker image prune）
        │
        ▼
部署完成（失败 → workflow 红 → 用上一个 vN tag 一键回滚）
```

> ⚠️ **现状标注（2026-07-28）**：CI 目前**只推镜像**——workflow 中的 migrate/deploy job 已注释；部署 = 手动执行 `docs/新aws账号/09-ssm-run-command/deploy-env.sh <env>`。上图 SSM 自动部署段为恢复注释后的目标态。

---

## 2. 仓库、分支与环境映射

两个仓库各有**自己的 workflow**，push 只构建/部署**自己的栈**（三栈独立部署是现有架构的优势，比"一条流水线全量重发"更快、影响面更小）：

| 触发 | Backend 仓库 | Frontend 仓库 | 目标环境 | 审批 |
|------|-------------|---------------|----------|------|
| push `test` 分支 | 构建 6 后端镜像 → 部署 infra+backend 栈 | 构建前端镜像 → 部署 frontend 栈 | **test**（非生产 VPC 的 test 服务器，§5.0） | 无，全自动 |
| push `uat` 分支 | 同上 | 同上 | **uat**（非生产 VPC 的 uat 服务器，§5.0） | 无（可选加） |
| push `main` 分支 | 构建镜像（自动）→ 部署 **prod**（人工审批） | 同左 | **prod**（生产 VPC，§5.0） | **GitHub Environment `main` Required reviewers** |
| `workflow_dispatch` 手动 | 选环境 + 选镜像 tag 部署（回滚入口） | 同左 | 任意 | prod 仍需审批 |

> 📌 **2026-07-29 拍板：GitHub environment 名 = 分支名，一律相同——`test` / `uat` / `main`。** 原先生产用的 `production` 是唯一例外命名，已废弃；两仓库 workflow 的 `environment:` 表达式与 `07-iam` 的 OIDC 信任策略（`repo:ORG/REPO:environment:main`）均已改名并重跑生效。注意区分：**部署环境（`DEPLOY_ENV`）仍叫 `prod`**，改名的只是 GitHub environment 这一个标识。

- 你草图里的 `develop` 分支在新仓库里不存在——日常开发对应 **`test` 分支**（dev 环境目前只在本地 Docker，不进 CI/CD）。
- 老仓库→新仓库的定时合并走**专用中间分支 `upstream-sync`**（2026-07-28 拍板）：老 main 先合到它、解冲突后再合入 `test`（触发 CI 验证），逐级晋级 `uat` → `main`。`upstream-sync` 分支本身不触发部署。
- `.github/workflows/` 是新仓库独有文件，老仓库没有，定时合并**不会产生冲突**。
- 并发保护：每个环境一个 `concurrency` group，防止两次 push 的部署互相踩踏。

---

## 3. 流水线环节详解

### 3.1 Lint + 编译检查

| 仓库 | 命令 | 现状说明 |
|------|------|----------|
| Backend | `black --check` / `isort --check` / `flake8`（等价 `make lint` 去掉 youtrack commit-msg 钩子） | 直接可用 |
| Frontend | `npm run lint`（eslint --max-warnings 0）+ `npx vite build`（编译验证） | **`tsc` 现有 16 个类型错误** → 编译检查暂用 `vite build`（与 `Dockerfile.novalidate` 一致）；`check:typescript` 作为**非阻断**警告 job 跑，修完 16 个错误后转为阻断并恢复 `npm run build` |

### 3.2 单元测试

| 仓库 | 命令 | 依赖 |
|------|------|------|
| Backend | `pytest -n logical --reruns 2`（等价 `make test`） | 需要**整套 compose 栈**（Postgres/Redis/Kafka/RabbitMQ）：workflow 里用 compose 起依赖服务 + 一份 **CI 专用 .env**（全部占位值，无真实密钥，可提交为 `deploy/.env.ci`） |
| Frontend | `npm test`（jest，现有 18 个测试文件） | 无外部依赖 |

> 后端测试较重（分钟级），先接入跑通；如太慢可后续拆"快测试 PR 必跑 / 全量测试合并后跑"。

### 3.3 Docker Build + Push ECR

沿用现有构建定义（Backend 仓库 `deploy/compose/{backend,frontend}.yml` 的 build 段，7 个镜像：backend `app/nginx/sms-sender/email-sender/ai-assistant/catalog-ocr` + frontend `app`），修正四个现存问题：

1. **tag 策略**（v1 已提出，此处落实到脚本层）：现状 `IMAGE_TAG=test|uat|prod` 可变覆盖 → 改为**双 tag**：
   - 不可变版本 tag：永久追溯，是**回滚的依据**。**2026-07-28 落地：版本 tag=`<env>-vN`（N=GitHub Actions run 序号 `run_number`，每次发布自增，如 `test-v12`），取代早期设计的 `<env>-<git-sha7>`；手动推送用 `<env>-manual-<sha7>`**；
   - `<env>`：浮动别名，EC2 compose 继续引用它（compose 文件零改动）。
   - `build-push.sh` 现在一次只推一个 tag，需小改支持双推（build 一次、`docker tag` + push 两次）。
2. **构建缓存**：GitHub runner 无本地缓存，poetry/npm/texlive 全量装一次很慢 → `docker/setup-buildx-action` + `cache-from/to: type=gha`。
3. **平台固定**：显式 `--platform linux/amd64`（落地时先 `aws ec2 describe-instances` 核对现有/新建 EC2 架构，Graviton 则改 arm64）。
4. **context 减肥**：后端根加 `.dockerignore`（`deploy/*.sql` 两个 65MB 快照 + `.git` 现在每次 build 全量发给 daemon）。

ECR 侧一次性配：**lifecycle policy**（每仓库保留最近 **5** 个镜像，已配置）+ scanOnPush。

### 3.4 部署：SSM Run Command（取代 SSH）

```
workflow deploy job（已通过 OIDC 拿到临时凭证）
  └─ aws ssm send-command
       --targets Key=tag:Environment,Values=<env>     # 2026-07-31 更正：标签键已改为 Environment（原 CssEnv 已废除）
       --document-name AWS-RunShellScript
       --parameters commands=["/opt/css-cicd/bin/deploy.sh <env> deploy <stack> <env>-vN"]
  └─ aws ssm wait / get-command-invocation        # 等执行结果，失败即 workflow 失败
```

- **不再需要**：开 22 端口、pem 私钥进 GitHub、`同步部署文件到EC2.ps1` 的手工 scp、"安全组放行本机 IP"的手工步骤。
- 前置：EC2 实例角色挂 `AmazonSSMManagedInstanceCore` + ECR 只读 + 读本环境 Parameter Store。
- 部署文件（compose ×3 + deploy.sh）随仓库版本化：deploy job 先把它们从 checkout 打包上传 S3（或直接 SSM 传输），EC2 端展开到 `/opt/css-cicd/` 再执行——**EC2 上的部署逻辑永远和仓库一致**，消灭"本地能跑、机器上是旧版"。

### 3.5 deploy.sh 增强（现有脚本三个缺口）

现有 `deploy.sh` 是 `pull + up -d --remove-orphans` 就结束。增强版补齐：

| 缺口 | 增强 |
|------|------|
| ❌ 无健康检查 | ① compose 给 `app`/`nginx`/`frontend`/`ocr-api` 补 `healthcheck`（现在只有 redis/rabbitmq/ocr-redis/worker 有）；② `up -d --wait` 等全部 healthy；③ 冒烟：`curl -sf localhost:8080/api/docs`、`curl -sf localhost:80/`、ocr-api 探活；任一失败脚本退出非 0 → workflow 红 |
| ❌ 无镜像清理 | 部署成功后 `docker image prune -f`（EC2 磁盘不再被旧层撑爆；原前端 GitLab CI 有这步，新脚本丢了） |
| ❌ 无回滚 | 部署时把"当前在跑的版本 tag（`<env>-vN`）"记录到 `/opt/css-cicd/.last_good_<env>`；回滚 = `workflow_dispatch` 选上一个 vN tag 重新部署（镜像不可变，回滚即换 tag 重拉） |

### 3.6 数据库迁移（独立 job，分级把关）

迁移**不混在 deploy 里**（现状本来就是独立 action，保持）：

| 环境 | 策略 |
|------|------|
| test | push 后自动 `deploy.sh test migrate`（test 数据可弃，不卡快照） |
| uat | 自动迁移，但**先自动打 RDS 快照**再执行 |
| prod | **人工审批 job**：先 RDS 快照 → 核对 `SELECT version_num FROM alembic_version` 在代码迁移链上 → 才 `alembic upgrade head`（生产库源自 preprod 数据迁移，虽然 2026-07-22 起 main=preprod 代码、迁移链应已对齐，此检查仍保留为保险） |

OCR 库不需要单独处理：`ocr-migrator` 容器每次 up 自动迁移（现有机制）。

---

## 4. 环境变量方案（核心问题的系统解法）

### 4.1 现状问题（实查确认）

1. `部署包/env/<env>/backend.env`（≈88 个变量）把**部署配置**（AWS/ECR/DEPLOY_*）和**运行时密钥**（DB 密码、JWT_SECRET、PASSWORD_SALT、S3 AK/SK、SMTP、Twilio、OpenAI/Gemini/Eden token）混在一个 gitignore 文件里——**CI checkout 后根本拿不到**，且靠人肉在多台机器间复制。
2. 前端 `VITE_*` 是**构建期烤进静态 JS** 的 → 每个环境必须单独构建镜像；构建时需要 `.env.<env>` 文件，而它**未入库**（在 runner 上 `COPY` 直接失败）。
3. 三处**强耦合键**靠人肉保持一致：`API_KEY == VITE_X_API_KEY`、`CATALOG_OCR_API_KEY == OCR_API_KEY`。
4. RDS 主密码由 Secrets Manager **自动轮换**（2026-07-31 更正：实为 **7 天**一轮换，此前误写 90 天），轮换后要人肉改 env 文件并 redeploy（迟早忘，忘了就是半夜故障）。
5. 老 GitLab CI 有 `cat $DOT_ENV` 把整份密钥打进日志的前科——新方案必须结构性杜绝。

### 4.2 设计：SSM Parameter Store 做**唯一事实源**

```
SSM Parameter Store（SecureString，KMS 加密）
  /css/test/backend.env      ← 整份后端运行时 env（advanced tier，8KB 上限够 88 变量）
  /css/test/frontend.env     ← 5 个 VITE_* 构建期变量
  /css/uat/...、/css/prod/... 同构

GitHub 侧零配置：角色 ARN 与 ECR 地址为非敏感固定值，直接写死于 workflow（2026-07-28 起）；无任何 Secret
```

| 消费者 | 时机 | 流程 |
|--------|------|------|
| **前端构建**（GitHub runner） | build 期 | workflow 经 OIDC → `aws ssm get-parameter /css/<env>/frontend.env --with-decryption` → 写入 `.env.<env>` 文件 → docker build（**全程不 echo/cat，GitHub Actions 对拉到的值自动脱敏**） |
| **后端运行**（EC2） | deploy 期 | deploy.sh 开头：`aws ssm get-parameter /css/<env>/backend.env --with-decryption > /opt/css-cicd/env/<env>/backend.env && chmod 600`（实例角色只授权**读本环境**路径）→ compose 照常 `--env-file` |
| **改一个运行时变量** | 任意 | 改 Parameter Store → 重跑 deploy job（后端 env 是运行时注入，**不用重构建镜像**）|
| **改一个 VITE_ 变量** | 任意 | 改 Parameter Store → 重跑前端 build+deploy（构建期烤入，必须重构建——这是 Vite 机制决定的）|

**为什么选 Parameter Store 而不是全上 Secrets Manager**：Secrets Manager 每 secret $0.40/月，三环境两文件不贵但每变量拆开就是 88×3 = 260+ 个；Parameter Store SecureString 标准层免费、advanced 层 $0.05/个/月，且 EC2/CI 读取路径一致。**例外**：RDS 主密码留在 Secrets Manager（已托管+轮换，不动）。

### 4.3 耦合键与轮换的两个专项

- **耦合键一致性校验**：CI 加一步"拉取 backend.env 的 `API_KEY` 与 frontend.env 的 `VITE_X_API_KEY` 比对（同理 OCR 两键），不一致直接 fail"——不打印值，只报"一致/不一致"。人肉同步从此有了自动兜底。
- **RDS 密码轮换解耦**：应用改用**专用低权 DB 账号**，密码存 Parameter Store、不参与自动轮换；Secrets Manager 里自动轮换（**7 天**，此前误写 90 天）的主密码只用于运维管理。轮换不再打断应用。（✅ 2026-07-30 已落地：账号为 `css_app_test`/`css_app_uat`（test 应用已切换用 `css_app_test` 连库），另有 `css_dev`/`css_ops`；自建账号密码固定不轮换，改密走 `docs/新aws账号/05-数据同步/change-db-password.sh`。）

### 4.4 环境变量的"分类账"（落地时按此拆分）

| 类别 | 例子 | 放哪 |
|------|------|------|
| 部署寻址（非密） | `AWS_REGION`、`ECR_REGISTRY`、`DEPLOY_ENV`、端口 | 可以直接进仓库的 `deploy/.env.<env>.public`（compose 插值用），或留在 Parameter Store 同一份里（**推荐后者，少一层拼接**） |
| 运行时密钥 | DB 口令、`JWT_SECRET`、`PASSWORD_SALT`、SMTP、Twilio、AI keys | Parameter Store SecureString |
| 构建期变量 | 5 个 `VITE_*` | Parameter Store（frontend.env） |
| CI 占位 | 单元测试用的假值 | 仓库内 `deploy/.env.ci`（明文、全占位，无真实值） |

> ⚠️ `PASSWORD_SALT` 迁移时**原样搬运**，绝不能重新生成（会导致全部存量用户密码失效——test 环境已经踩过这个坑）。

### 4.5 三环境 AWS 凭证隔离（2026-07-28 用户要求：key 不能同一个，权限按需）

每个环境一套**独立**凭证/角色，互不可见、权限只够本环境用：

| 凭证 | test | uat | prod | 权限范围 |
|------|------|-----|------|----------|
| CI/CD 部署角色（OIDC，无静态 key） | `css-deploy-test` | `css-deploy-uat` | `css-deploy-prod` | ECR push、SSM send-command（限定 `CssEnv=css-<env>` 标签的实例）、读写 `/css/<env>/*` 参数、RDS 快照（uat/prod）；信任策略锁定 `Chain-Serve-Solutions/<repo>` 对应分支 |
| EC2 实例角色 | `css-ec2-test` | `css-ec2-uat` | `css-ec2-prod` | SSM 托管核心、ECR **只读**、读 `/css/<env>/*` 参数、写本环境 CloudWatch 日志 |
| 应用 S3 静态 key（代码 `s3_settings.py` 要求显式 key） | IAM 用户 `css-app-test` | `css-app-uat` | `css-app-prod` | **仅本环境 S3 桶**读写，无其他任何权限；AK/SK 只存本环境 Parameter Store 的 backend.env |
| 人工运维 | 现 `css-test`（Admin）——落地后建议改名 `css-ops` 并按需收权 | 同左 | 同左 | 控制台/CLI 管理 |

规则：**任何静态 key 不跨环境复用**；泄露任一环境的 key 影响面被锁死在该环境；prod 三套凭证在阶段三创建时全新生成。

---

## 5. 目标基础设施拓扑与三环境部署详解

### 5.0 两套 VPC 拓扑（v2.2：全私有子网 + 堡垒机唯一入口，2026-07-28 拍板）

AWS 账号 `582797602427` / us-east-1，新建两套 VPC，环境彻底隔离。**所有应用服务器和 RDS 一律私有子网，管理访问只能经堡垒机**；管理白名单 IP：**`221.214.0.190/32`**（你的开发 IP）。

```
VPC css-non-prod（10.20.0.0/16）
├── 公有子网 ×2（跨 2 AZ）
│   ├── ALB css-test ✅ + ALB css-uat ✅（2026-07-29：每环境一个，名字=环境名；旧共享 ALB 与 Host 分流已作废）
│   │   css-test-524317374.us-east-1.elb.amazonaws.com / css-uat-1366981991.us-east-1.elb.amazonaws.com
│   └── EC2 网关机（t4g.micro，绑 EIP 3.225.148.166）—— 2026-07-29 起只剩两职：
│       ① 堡垒：22 ← 仅 221.214.0.190/32，SSH ProxyJump 进私网
│       ② NAT：test/uat 出网（ECR/S3/SSM/第三方 API）经它转发（省 NAT 网关 $32/月）
│          ⚠️ SG 里的 `10.20.0.0/16 全协议` 是 NAT 回程，删了 test/uat 断网
│       ~~③ 反代 nginx :80/:8080~~ 已停用禁用、SG 规则已撤（12-alb/revoke-gw-proxy.sh）
└── 私有子网 ×2（跨 2 AZ，RDS 子网组要求）
    ├── EC2 test 应用服务器（Linux，t3.large 2c8G，跑 test 三栈，无公网 IP）
    ├── EC2 uat  应用服务器（Linux，t3.large 2c8G，跑 uat  三栈，无公网 IP）
    └── RDS css-non-prod（PostgreSQL 16 单实例，✅ 已建成并载入 test 数据）
        库：css-test-main / css-test-ocr / css-uat-main / css-uat-ocr

VPC css-prod（10.10.0.0/16）
├── 公有子网 ×2（跨 2 AZ）
│   ├── ALB（产品对外入口；HTTPS/ACM 上域名后启用 443）→ 转发 prod 应用机
│   ├── NAT 网关（prod 出网走托管 NAT，可靠性优先）
│   └── EC2 堡垒机（t4g.nano，绑 EIP；22 ← 仅 221.214.0.190/32）
└── 私有子网 ×2
    ├── EC2 prod 应用服务器（Linux，c5.xlarge 起，跑 prod 三栈，无公网 IP）
    └── RDS css-prod（PostgreSQL，Multi-AZ + 自动备份）
        库：css-prod-main / css-prod-ocr
```

**安全组链（最小化）**：

| SG | 入站规则 |
|----|----------|
| 网关/堡垒 SG | 22、80、8080 ← `221.214.0.190/32`（仅此 IP） |
| 应用机 SG | 80 ← 网关 SG（非生产）/ ALB SG（prod）；22 ← 网关/堡垒 SG |
| RDS SG | 5432 ← 应用机 SG + 网关/堡垒 SG；**不开公网** |
| ALB SG（prod） | 80/443 ← 0.0.0.0/0（产品对外） |

**访问方式**：
- test 页面：`http://<网关EIP>/`；uat 页面：`http://<网关EIP>:8080/`（都只有你的 IP 能打开）；
- SSH 上应用机：`ssh -J gateway test-private-ip`（ProxyJump）；连 RDS：经网关机 `-L` 隧道 psql；
- prod 页面：ALB DNS（上域名+ACM 后转 HTTPS）；
- **CI/CD 部署链路不经过堡垒机**：GitHub Actions → SSM Run Command → 私网应用机（SSM 走 NAT 出站长连接，无需入站端口）。堡垒机与 SSM Session Manager 互为备份运维通道。
- 每 VPC 加免费的 **S3 Gateway Endpoint**（S3 流量不过 NAT，省流量费）。

**规格依据**：现有 test 机是 m7i-flex.large（2c**8G**）跑 13 个容器刚好，故新 test/uat 用同内存档 t3.large（2c8G）；4G 档必 OOM，不再推荐 t3.medium。

**现有资源迁入新 VPC**（现 test EC2 与 RDS 在默认 VPC）：
- EC2 无法跨 VPC 移动 → 在新 VPC **重建** test 服务器（数据全在 RDS/S3，CI/CD 跑通后重建 = 装 docker + 挂实例角色 + 跑一次 deploy）；
- RDS 迁移 = **新建实例 `css-non-prod` + `docs/新aws账号/05-数据同步` 恢复数据到新库名**（v2.2 拍板，取代早期快照恢复方案；✅ 2026-07-28 已完成——新实例建于新 VPC，`css-test-main`/`css-test-ocr` 已用 `restore-dump-via-gw.sh` 载入 preprod 备份，旧默认 VPC 实例已删）；
- 前端 `VITE_WS_BASE_URL` 现在烤的是服务器公网 IP → 私有化后**改烤网关 EIP**（非生产）/ ALB 域名（prod），服务器重建不再影响前端镜像。

**月成本粗估**（us-east-1 按需价，v2.2 私有子网版）：

| | 项 | 估算 |
|---|------|------|
| 非生产 | test t3.large + uat t3.large | ~$120 |
| | 网关机 t4g.micro（堡垒 + NAT 两职；反代已收） | ~$6 |
| | RDS css-non-prod（t4g.micro，✅ 已建） | ~$15 |
| | **ALB ×2**（`css-test` + `css-uat`，✅ 已建，每环境一个） | ~$40 |
| | 公网 IPv4（EIP 1 + ALB 节点 4）/EBS/S3/杂项 | ~$34 |
| | **小计** | **~$215/月** |
| 生产 | EC2 c5.xlarge（可先 c5.large ~$70 观察负载） | ~$140 |
| | 堡垒机 t4g.nano | ~$3 |
| | NAT 网关（+流量） | ~$35 |
| | RDS css-prod（t4g.medium Multi-AZ + 备份） | ~$120 |
| | ALB `css-prod` | ~$20 |
| | 公网 IPv4×4 / S3 / CloudWatch / 杂项 | ~$40 |
| | **小计** | **~$355/月**（预留实例可再降 30%+） |

> ⚠️ **账号计划阻断（2026-07-28 实查）**：账号 `582797602427` 目前是 **FREE plan**，剩余 credits **$53.87**（2027-01-03 到期）。本拓扑月费约 **$570**（2026-07-29 ALB 改每环境一个后 +$40+）。Free plan 撑不过几天且部分计费资源可能被直接拒建。**必须先在控制台升级为 Paid plan**（Billing → 升级，绑付款方式——需账号所有者操作），再创建 EC2/RDS/NAT/ALB/EIP。零成本资源（VPC/子网/SG/IAM/OIDC/Parameter Store/S3 端点）不受影响，可先行创建。

### 5.1 test —— push 即上（全自动）

**基础设施**：非生产 VPC 的 test 服务器 `css-test-app`（✅ 2026-07-30 重建后为 `i-0cb9b69b9eb19a9aa`，10.20.10.10 不变，三栈已部署）+ RDS `css-non-prod` 的 `css-test-main`/`css-test-ocr` 库（✅ 已载入 preprod 数据并于 2026-07-29 脱敏）+ 入口 ALB `css-test`（✅ `css-test-524317374.us-east-1.elb.amazonaws.com`）+ S3 桶 `css-test-582797602427`（✅）。（过渡期方案已作废：旧默认 VPC 的 test EC2 `i-08e110b5a5425980d` 与旧 RDS 实例均已于 2026-07-28 删除。）

**一次典型发布**：
1. 你（或定时任务把老仓库合并过来后）`git push origin test`；
2. 两仓库各自触发 workflow：lint → 单测 → build → push ECR（`test-vN` + `test` 双 tag）；
3. deploy job 经 SSM 让 test 服务器跑增强版 `deploy.sh test deploy backend`（前端仓库则 `frontend` 栈）：渲染 env → pull → up --wait → 冒烟 → prune；
4. migrate job 自动跑 `alembic upgrade head`；
5. 全绿 ≈ 10~15 分钟后 test 环境就是这次 push 的代码。失败在哪一步，GitHub 的红叉就停在哪一步。

### 5.2 uat —— 从 `ops` 合入（自动，带快照）

**基础设施**：非生产 VPC 的 uat 服务器（与 test 同规格、独立一台——现有 2 vCPU 机器跑一套全栈已经紧张，gunicorn 曾 CPU 崩溃循环，不与 test 同机）；数据库共用 RDS `css-non-prod`（✅ 实例已建成），建 `css-uat-main`/`css-uat-ocr` 库（`docs/新aws账号/05-数据同步/create-databases.sh`）。

**发布流**：`git checkout uat && git merge ops && git push origin uat` → 同一条流水线自动跑，差异只有两点：目标机 tag=`Environment=css-uat`、migrate 前**自动打 RDS 快照**。

> ⚠️ **2026-08-22 分支重建后不再有"从 test 晋级"**：`uat` = main + ops，`test` = main + ops + **support-demo**（老团队线）。
> **绝不能 `git merge test` 到 uat**——会把 uat 的 alembic 头从 `b3d9f1a2c4e5` 变成 `e8f2a4b6c1d3`。

### 5.3 prod —— main 分支 + 手动 Run workflow（半自动）

**基础设施**：生产 VPC 全套（§5.0：应用机 + 堡垒机 + 独立 RDS css-prod + ALB/ACM + prod S3 桶），安全硬化细节沿用 [01-独立服务器方案](01-独立服务器方案.md) §5 对照表。**RDS 与非生产完全分开**。

**发布流**：
1. uat 验证 OK → `ops` → `main` 走 PR 合并 → `git push origin main`；
2. workflow 自动跑完 lint/测试/build/push（镜像 `prod-vN` 已就绪在 ECR）；
3. **push `main` 到此为止——只构建镜像、不部署**。GitHub Free 私有仓库**不支持环境审批**，所以人工闸改成"手动触发"：Actions → CICD → **Run workflow**（environment=prod；`image_tag` 留空=重新构建并部署，填 `prod-vN`=回滚到该版本）；
4. 手动触发后 → migrate job（快照 + alembic_version 核对 + upgrade）→ deploy job（SSM → prod 应用机）→ 冒烟；
5. 出问题 → `workflow_dispatch` 选上一个 `prod-vN` tag 重新部署即回滚（分钟级）。

> 三环境是**同一份 workflow 代码**，差异全部收敛在：分支名、`CssEnv` 标签、Parameter Store 路径、是否审批、迁移前置动作。不存在"三套各写各的"。

---

## 6. workflow 文件设计（骨架；已按此实现于两仓库 `.github/workflows/cicd.yml`，变量为仓库级 `AWS_ROLE_ARN_<ENV>`）

两仓库各一个主 workflow，结构相同（此处以 backend 为例；前端把 build 矩阵换成单镜像、栈换成 frontend）：

```yaml
# Chain-Service-Solutions-Backend: .github/workflows/cicd.yml
name: cicd
on:
  push: { branches: [test, uat, main] }
  workflow_dispatch:
    inputs:
      environment: { type: choice, options: [test, uat, prod] }
      image_tag:   { description: 回滚用：指定 <env>-vN tag, required: false }
concurrency: cicd-${{ github.ref_name }}      # 同环境部署不并行
permissions: { id-token: write, contents: read }

env:
  DEPLOY_ENV: ${{ inputs.environment || (github.ref_name == 'main' && 'prod' || github.ref_name) }}

jobs:
  lint:      # black/isort/flake8
  unit-test: # compose 起依赖 + pytest（用 deploy/.env.ci 占位值）
  build-push:
    needs: [lint, unit-test]
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4     # OIDC
        with: { role-to-assume: ${{ vars.AWS_ROLE_ARN }}, aws-region: us-east-1 }
      - uses: aws-actions/amazon-ecr-login@v2
      - uses: docker/setup-buildx-action@v3
      - run: ./deploy/aws/build-push.sh $DEPLOY_ENV $DEPLOY_ENV-v$GITHUB_RUN_NUMBER   # 双 tag 增强版（<env>-vN + <env>）
  migrate:
    needs: build-push
    environment: ${{ env.DEPLOY_ENV == 'prod' && 'main' || env.DEPLOY_ENV }}  # environment 名=分支名；prod → main
    steps: [快照(非test) → SSM 执行 deploy.sh migrate]
  deploy:
    needs: migrate
    environment: ${{ env.DEPLOY_ENV == 'prod' && 'main' || env.DEPLOY_ENV }}
    steps:
      - 上传部署包(compose+deploy.sh) → SSM send-command 执行增强版 deploy.sh → wait 结果
```

前端 workflow 的 build 步骤多一个前置：`aws ssm get-parameter /css/$DEPLOY_ENV/frontend.env` → 写 `.env.$DEPLOY_ENV` → `docker build -f Dockerfile.novalidate --build-arg ENV_FILE=.env.$DEPLOY_ENV --build-arg NGINX_CONF=nginx.aws.conf`。

---

## 7. 一次性前置准备（含 4 个阻断项）

### 仓库侧（✅ 已全部完成，2026-07-28；留档备查）

| # | 事项 | 说明 |
|---|------|------|
| 🔴1 | **把部署编排收编进 Backend 仓库 `deploy/`** | compose ×3、deploy.sh（增强版）、`.env.*.example`、`.env.ci`。现状 `CSS_backend-main/deploy/` **整个目录未 tracked**，checkout 后 CI 无米下锅。以 `部署包/` 的最新版为准收编（它比 deploy/ 下的更新）。**同时 `.gitignore` 掉 `deploy/.env.test`**——它现含真实密钥，`git add deploy/` 前必须先排除 |
| 🔴2 | **前端仓库提交 `Dockerfile.novalidate` + `nginx.aws.conf`** | 两个文件都未 tracked，而它们是 AWS 构建的唯一入口 |
| 🔴3 | **前端 `.env.<env>` 不入库**，改由 CI 从 Parameter Store 生成 | 现 `.env.test` 未 tracked 且含真实 key，保持不入库 |
| 🔴4 | 后端根加 `.dockerignore` | 排除 `deploy/*.sql`（130MB）、`.git` 等；顺带把两个 SQL 快照移出仓库 |
| 5 | 删除两仓库的 `.gitlab-ci.yml` | GitLab 时代遗留，且前端那份有 `cat $DOT_ENV` 泄密前科 |
| 6 | compose 给 `app`/`nginx`/`frontend`/`ocr-api`/`kafka` 补 healthcheck | §3.5 的 `--wait` 依赖它 |
| 7 | **`.idea` 禁止上传**：backend 仓库 `.idea/` 已被 git 跟踪 → `git rm -r --cached .idea` + `.gitignore` 加 `.idea/`；frontend 仓库 `.gitignore` 补 `.idea/` | 用户 2026-07-28 指令 |

### AWS 侧

1. **GitHub OIDC provider** + 三个环境部署角色（最小权限：ECR push、SSM send-command[限定 CssEnv 标签]、Parameter Store 读本环境、RDS 快照、uat/prod 各自资源）——信任策略锁定 `Chain-Serve-Solutions/<repo>:ref:refs/heads/<branch>`；
2. 现有 test EC2（过渡期）：实例角色加 `AmazonSSMManagedInstanceCore` + Parameter Store 读 `/css/test/*`；打 `CssEnv=css-test` 标签；
3. Parameter Store 写入 `/css/{test,uat,prod}/{backend,frontend}.env`（test ✅ 已灌入；uat/prod 以工作区根 `deploy-env/<env>/*.example` 为底稿；prod 密钥**全新生成，勿复制**）；
4. 建 `css_app` 低权 DB 账号（§4.3）；ECR lifecycle policy；
5. **VPC css-non-prod 全套**（§5.0）：子网/SG/EIP（✅）+ 网关机（✅）+ 新建 RDS css-non-prod 并用 05-数据同步恢复数据（✅ test 两库已载入）+ test/uat 应用机（⏳ 06-ec2）+ `css-uat-main`/`css-uat-ocr` 建库（⏳）；
6. **VPC css-prod 全套**（阶段三）：子网/SG + 应用机 + 堡垒机 + RDS css-prod（Multi-AZ）+ ALB/ACM + prod S3 桶。

### GitHub 侧

两仓库各建 Environments：`test`、`uat`、`main`（**2026-07-29 起 environment 名=分支名 test/uat/main**，弃用 `production`；最后一个配 **Required reviewers**——Free 私有仓库不提供，实际改为 workflow 内置手动触发闸）；仓库级 Variables 配 `AWS_ROLE_ARN_TEST/UAT/PROD` + `ECR_REGISTRY` 四个（值见 docs/环境/配置速查.md）。分支保护：`main` 禁止直推可选开启（与"定时合并"流程协调后再定）。

---

## 8. 与你草图的对照

| 你的草图 | 本方案 | 变化理由 |
|----------|--------|----------|
| push `develop` 触发 | push `test`/`uat`/`main` 触发 | 对齐新仓库三分支模型；main=prod 必须加审批闸 |
| 编译、单元测试 | 保留，前端 tsc 暂非阻断 | 16 个存量类型错误未修 |
| Docker Build → Push ECR | 保留 + buildx 缓存 + 双 tag + 平台固定 | 提速、可回滚、防架构错配 |
| SSM Run Command → EC2 | 完全一致（现状是 SSH+pem，本方案正是切到你草图的 SSM 模式） | 免 22 端口/pem/IP 白名单 |
| docker pull / compose up / 清理旧镜像 / Health Check | 保留；清理与健康检查是**现有脚本缺失、本方案补上**的 | `up -d --wait` + 冒烟 + prune |
| （无） | 环境变量：Parameter Store 单一事实源 + 耦合键校验 + RDS 密码解耦 | 你点名要解决的问题 |
| （无） | 迁移独立 job 分级把关；prod 人工审批；vN tag 回滚 | 生产安全底线 |

---

## 9. 审计问题规避（承接 v1，全部保留）

| 审计问题 | 本方案对应 |
|----------|-----------|
| 前端 CI `cat .env` 泄密 | CI 从 Parameter Store 拉取（自动脱敏），结构上无 `cat`；删除旧 `.gitlab-ci.yml` |
| runner 挂 docker.sock、与业务同机 | GitHub 托管 runner 构建 + SSM 远程部署，业务机零 CI 组件 |
| 静态 AWS AK/SK | OIDC，GitHub 不存任何长期密钥 |
| 密钥明文 `.env` 人肉流转 | Parameter Store SecureString + 实例角色按环境隔离读取 |
| 可变镜像 tag 无回滚 | `<env>-vN` 不可变版本 tag + lifecycle（每仓库保留 5 个）+ dispatch 回滚 |
| 部署无验证、down+up 停机 | `--wait` + 冒烟；（真零停机留给方案二 ECS） |
| 误发生产 | `main` Environment Required reviewers（environment 名=分支名） |
| 迁移卡发布 | 迁移独立 job；uat/prod 先快照；prod 加 alembic_version 核对 |

---

## 10. 分阶段落地

| 阶段 | 内容 | 前提 |
|------|------|------|
| **一：test 跑通全链**（先做） | 仓库侧 7 项准备（✅ 已全部完成，2026-07-28） → AWS 侧 1-4 → 两仓库 workflow 上线 → 在**现有** test EC2 上 push test 分支验证全绿 | 现有资源即可，**零新增基础设施** |
| **二：css-non-prod VPC 落地** | 建非生产 VPC（✅）+ 网关机（✅）+ 新建 RDS css-non-prod 并 05-数据同步迁数据（✅ test 两库已载入）+ 退役默认 VPC 旧 EC2/RDS（✅ 已删）→ 建 test/uat 应用机（06-ec2，⏳）→ 部署 test（现阶段手动 deploy-env.sh）→ 上线 uat（`css-uat-main`/`css-uat-ocr` 库 + `/css/uat/*` 参数，同 workflow 直接生效） | 阶段一流水线全绿 |
| **三：css-prod VPC 上线** | 建生产 VPC 全套（§5.0 + 01-方案一硬化表）→ `main` Environment 审批（名=分支名）→ 首次全量部署 + 数据迁移（`docs/老aws账号/`） | prod 子网模式拍板（§11） |

---

## 11. 待确认的决策点

已拍板（2026-07-28）：~~编排文件位置~~ → **进 Backend 仓库 `deploy/`，方案文档留在工作区 `docs/`（代码仓库之外）**；~~uat 是否独立服务器~~ → **两套 VPC，test/uat 各一台 + 堡垒机，RDS prod/非生产各一个**（§5.0）。

v2.2 已拍板：~~prod 子网模式~~ → **全部私有子网 + 堡垒机唯一管理入口**（prod 挂 NAT 网关，非生产网关机兼 NAT）。

补充拍板（2026-07-28 二次）：非生产 RDS 迁移方式 = **新建实例 `css-non-prod` + `docs/新aws账号/05-数据同步` 恢复**（✅ 已完成：新实例建于新 VPC，旧默认 VPC 同名实例已删）；库名规范 = `css-<env>-main` / `css-<env>-ocr`；资源创建脚本收敛到工作区 `docs/新aws账号/`。

仍待确认 / 待用户操作：

1. 🔴 **升级账号为 Paid plan**（FREE plan 剩 $53.87 credits，计费资源创建的前置条件，只有账号所有者能操作）；
2. 迁移分级：test 自动 / uat 自动+快照 / prod 审批——是否接受 test 无快照自动迁；
3. 前端 16 个 tsc 错误：短期 novalidate 继续（本方案默认），是否排期修掉后恢复类型阻断；
4. `main` 分支是否开分支保护禁止直推（与老仓库定时合并流程有交互，需一起定）；
5. 应用机规格：test/uat 各 t3.large（2c8G，~$60/月/台，对齐现机 8G 内存）、prod c5.xlarge 起（可先 c5.large 观察）。
