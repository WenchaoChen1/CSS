# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在本仓库中处理代码时提供指导。

## 仓库结构

这是一个 **CSS (Chain Serve)** 的 monorepo 式工作区，包含两个独立部署的项目外加一份数据库快照：

| 路径 | 说明 |
|------|------------|
| `CSS_backend-main/` | Python / FastAPI 后端（Poetry、Docker Compose、Alembic） |
| `CSS_frontend-main/` | React 19 + TypeScript + Vite SPA |
| `备份/` | 数据库/S3/docker-env 迁移产物（含旧快照，gitignore；原根目录 postgres_backup_20260628.sql 已归档移除） |

两个项目拥有**各自独立的工具链、CI 流水线和 `.env` 文件**。请分别独立处理它们——运行命令前先 `cd` 进入相应项目目录。

---

## 环境 → AWS 账号映射（重要，先读）

本项目有**两个 AWS 账号**，六个环境按名称固定归属，**切勿混淆**：

| 环境 | AWS 账号 | 区域 | 角色 |
|------|----------|------|------|
| `staging` / `dev` / `preprod` | **老账号 `021213872872`** | eu-central-1 | 原团队遗留环境（全容器、无 RDS）→ **数据迁移的来源** |
| `test` / `uat` / `prod` | **新账号 larry `582797602427`** | us-east-1 | 我方新建环境（EC2 + ECR + RDS + S3）→ **部署目标** |

- **老账号（迁移源）**：只有 `preprod`(3.74.51.100) 已开通 SSH；`dev`/`staging` 待开通。用 `docs/老aws账号/` 的脚本把 DB / docker env / S3 拉到本机 `备份/`。
- **新账号（部署目标，2026-07-29 实查）**：旧默认 VPC 的 test 机已删除，全部资源在新 VPC。网关机 `css-non-prod-gw`(i-08b0ef319d08eae38, EIP 3.225.148.166, **只剩堡垒 SSH + NAT 出网**，nginx 反代已停用)；应用机 `css-test-app`(10.20.10.10, m7i-flex.large, **三栈已部署可用**) 与 `css-uat-app`(10.20.11.10, 同规格, **三栈已部署可用**)——两台根卷 2026-08-05 自 50 扩到 **100GB**（旧 50GB 被 docker 历史镜像撑到 98%，CI 部署失败）；**prod 全套已于 2026-08-07 开闸建成三栈可用**：应用机 `css-prod-app`(i-03857b9ec7bd372d9, 10.10.10.10, m7i-flex.xlarge, 钥 css-prod-app.pem) + 托管 NAT + ALB `css-prod-469103402.us-east-1.elb.amazonaws.com`(80→301+443 通配符证书；域名 prod-demo.chain-serve.com ⏳待 GoDaddy CNAME)。RDS `css-non-prod`(PG16.14, **db.t4g.small**——2026-08-03 账号升 Paid plan 当天自 micro 升配, 私有子网, test+uat 共用；库 `css-test-main`/`css-test-ocr` 已载入 preprod 数据并**已脱敏**——邮箱前缀 1、口令统一 `Test1234!`)；**独立 RDS `css-prod`**(PG16.13, db.t4g.medium, Multi-AZ, endpoint `css-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com`；库 `css-prod-main`/`css-prod-ocr` 2026-08-07 载入当日 preprod 备份并按 **prod 专用口径脱敏——邮箱前加 1、手机号后加 1、口令未动**（保留 preprod 原口令+原 salt），账号 `css_app_prod`/`css_ops` 见 deploy-env/密码.local.md §一B)。入口：**每环境一个 ALB**（`css-test`/`css-uat`/`css-prod`）。**资源命名一律 `css-non-prod-*` / `css-prod-*`（带连字符）**。CloudWatch 监控 test/uat 已配（**共 22 告警**：test 7 / uat 7（各含 2026-08-05 新增的 CloudWatch Agent 磁盘>80%/内存>85% 两条）/ **组级共享 8**（`css-non-prod-rds-*`×5 + `css-non-prod-bastion-*`×3，2026-08-04 自 test 代持移入组级 stack `css-non-prod/monitoring`，自带 SNS 主题 `css-non-prod-alarms`——收到 `css-non-prod-*` 告警 = 共享资源出事、test/uat 都受影响）+ test/uat 各一 Dashboard；SNS 订阅 charles 邮箱三主题已确认，**qq 邮箱对新主题 `css-non-prod-alarms` 待点确认**）；**账号已于 2026-08-03 升 Paid plan**（原 Free plan 拦截解除；credit 余 ~$46 继续抵扣，日耗 ~$8）；**RDS 已同日升 db.t4g.small**（uat 上线前置已满足——升配前 swap 单调爬升 ≈13MB/天 已在换页，升配后 FreeableMemory 88MB→1078MB、swap 清零，详见 `css-terraform/环境实况/aws服务-服务技术文档.md` §3.1）；**css-prod 计费资源已于 2026-08-07 开闸建成**（prod 监控 12 告警+Dashboard+SNS `css-prod-alarms` 双邮箱⏳待确认；镜像 backend `prod-v50`/frontend `prod-v35`——**ops 已一次性合入 main**（用户拍板），push main 自动构建 prod 镜像，部署走 `09/deploy-env.sh prod` 或 Actions 手动 Run workflow）；本地开发直传 S3 走桶 `css-dev-582797602427` + 用户 `css-app-dev`（key 在 deploy-env/dev）。运维凭证与命令全集见`docs/环境运维执行脚本/运维访问速查.local.md`（gitignore）。
- 脚本按账号分放（2026-07-28）：`docs/环境运维执行脚本/`=新账号资源创建/推镜像（01-vpc~10），`docs/老aws账号/`=老账号数据拉取；**`部署包/` 已整体退役并入 `CSS_backend-main/deploy/`**（compose 编排、本地 dev、EC2 端 deploy.sh；env 配置 2026-07-28 再迁出到工作区根 `deploy-env/`）；CI/CD 已落新组织两仓库（`.github/workflows/cicd.yml`），手册在 `docs/环境运维执行脚本/`（总流程在其 README，组件手册在 08/09 文件夹）。

---

## 项目交接状态（先读）

本代码库正在**从另一个团队接手**。以下是从代码本身看不出来的关键背景：

- **只有 `main`（来自 GitHub）可用。** 对方团队正在进行的开发工作放在 **GitLab 上，从未推送到 GitHub**，因此这里的代码可能落后于他们真实的开发环境。
- **数据库快照比代码新。** `postgres_backup_20260628.sql`（2026-06-28）比 `main`（最新迁移 `2026_04_10`，revision `c868e4eb8b15`）领先约 2.5 个月。它的 `alembic_version` 极可能指向这里 `migrations/versions/` 中**并不存在**的 revision——**切勿**对导入的快照运行 `alembic upgrade/downgrade`。
- **快照是二进制格式（`pg_dump -Fc`），尽管扩展名是 `.sql`**（文件头为 `PGDMP`）。请用 `pg_restore` 恢复，切勿用 `psql`。

### 本地数据库（三个，都在同一个容器 `css-backend__db` 内）

| 数据库 | 来源 | 使用方 |
|----------|--------|---------|
| `css_dev` | `alembic upgrade head` + **尽力而为的快照数据导入** | **应用本身（工作库，`POSTGRES_DB=css_dev`）** |
| `postgres` | 干净的 `alembic upgrade head`，空库 | 干净的代码 schema 基线 / 参考 |
| `css_dump` | 原样恢复的快照（`pg_restore`） | schema 与数据对比——应用**不会**连接这里 |

应用和 alembic 都以 `POSTGRES_DB` 所指定的库为目标（见 `config/postgres_settings.py`；`migrations/env.py` 复用同一套配置），因此 alembic 只会操作被指定的那个库。通过 Windows override，Postgres 暴露在宿主机的 `localhost:5432`（postgres/postgres）上。

**`css_dev` 的数据是通过 dblink 从 `css_dump` 尽力而为导入的**（原 `db_compare/` 调和脚本，**该目录已于 2026-07-28 删除**——main 已是 preprod 代码，旧 css_dev 调和流程作废），只复制两边 schema 共有的列，并关闭了 FK 检查。由于两边 schema 已经分叉，`css_dev` 相对纯代码 schema 存在以下**有意为之的分歧**（仅限 dev）：
- `businesstype` 枚举增加了值 `MANUFACTURER`（快照中带有该值）。
- `company.user_id` 的 `NOT NULL` 被去掉（快照中的行没有 owner；那是仅存在于代码中的 user_management 列）。
- `company_audit_log` 是**空的**（其 id 列在代码中是 uuid、在快照中是 integer——尚未解决的类型分歧）。
- 那 14 张仅快照中有的 `manufacturer_*` / `payment_method` / `product_attribute*` 表在 `css_dev` 中**并不存在**（代码中没有对应的表），因此这部分数据被丢弃了。

~~通过 `db_compare/*.sql` 从零重建 `css_dev`~~ **已作废（2026-07-28）**：`db_compare/` 已删除；旧 css_dev 对应旧代码线，勿在其上跑新迁移。开发库以 preprod 备份恢复或空库 `alembic upgrade head` 重建（见 `备份/数据库/`）。

对比两者即可发现 GitHub 上缺失了哪些迁移：
```
docker exec css-backend__db pg_dump -U postgres --schema-only --no-owner postgres  > schema_code.sql
docker exec css-backend__db pg_dump -U postgres --schema-only --no-owner css_dump > schema_dump.sql
```

### `.env` 文件（⚠️ 上游遗留模型说明——本地 dev 已改走工作区 `deploy-env/dev/backend.env` + `本地dev.ps1`，本节仅供参照上游 Makefile 流程）

两个项目都需要一个 `.env`（现已存在，由各自的 `.env.example` 生成）。两条必须遵守的：
- 后端 `.env` 是**运行时的 `env_file`，不会烤进镜像**——修改它只需重启容器，无需重新构建。
- 后端 `API_KEY` **必须等于**前端 `VITE_X_API_KEY`，否则每个请求都会被 `/api` 的 `check_api_key` 守卫拒绝。前端指向 `http://localhost:8080`（后端 nginx 端口 = 后端 `PORT`）。
- **`.env.example` 并不完整。** `config/catalog_ocr_settings.py` 需要 `CATALOG_OCR_BASE_URL` 和 `CATALOG_OCR_API_KEY`（无默认值），但 `.env.example` 中没有它们。缺少它们会抛出 pydantic `ValidationError`，导致**全部四个**应用入口都无法启动（共享的 `Settings` 无法实例化）。生成的 `.env` 中已包含这两项。核对环境变量时，请以 `config/*.py` 中的 pydantic 类为准，而不是 `.env.example`。

### 后端代码变更后的重新部署

代码确实会烤进镜像（`COPY src/ .`），因此**代码**变更需要重新构建（env 变更则不需要）。本地 dev（2026-07-28 统一模型）：栈=`deploy/compose/dev.yml`（含本地 Postgres/kafka/kafka-ui/pgadmin——**认证依赖 Kafka**：auth 的 DI 会立即针对 `kafka:9092` 启动一个 producer，因此没有它登录会报 500），配置=工作区根 `deploy-env/dev/backend.env`（2026-07-28 env 整体迁出仓库），入口：
```
.\deploy\windows\本地dev.ps1 [up|down|build|rebuild|migrate|ps|logs|restart|front]
```
仓库根 `redeploy.ps1` 是它的薄封装（rebuild）。**test / uat / prod 走 CI/CD**（GitHub Actions → ECR 双 tag `<env>-vN` 版本号+`<env>` 浮动，lifecycle 保 5 → 部署暂为手动 `docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh`），编排=`deploy/compose/{infra,backend,frontend}.yml`（独立项目 `css-<env>-*` 共享网络 `css-<env>-net`），运行时配置唯一事实源=SSM Parameter Store `/css/<env>/backend.env`（deploy.sh 自动渲染；本地底稿在工作区 `deploy-env/<env>/`）。AWS 栈无 db/pgadmin 容器（Postgres 在 RDS；新库名规范 `css-<env>-main`/`css-<env>-ocr`）。前端镜像构建期烤入 `VITE_*`（来自 `/css/<env>/frontend.env`，用 `Dockerfile.novalidate`——tsc 尚有 16 个存量类型错误）。手册见工作区 `docs/环境运维执行脚本/`（README 总流程 + 08/09 组件手册）；deploy 结构见 `deploy/README.md`。

### Windows 宿主机注意事项（同上：core_app compose + 根 .env 属上游遗留模型，本地 dev 一律走 deploy/windows/本地dev.ps1）

宿主机上没有 `make` / `pg_restore` / `sudo`（只有 Docker Desktop）。请使用 `docker compose` 原生命令——`Makefile` 只适用于 Linux（它的 `makemigrations` / `poetry_*` 目标会调用 `sudo chown`，在这里跑不起来）。在 `CSS_backend-main/` 目录下运行 compose，并传入 `--env-file .env`，这样 `${VAR}` 插值才能解析（核心栈位于 `core_app/docker-compose.yml`；根目录的 `docker-compose.yml` 还额外 `include` 了 OCR + ai_assistant 服务，它们需要额外的 API key）。

---

## 后端（`CSS_backend-main/`）

FastAPI 应用以多服务 Docker Compose 栈的形式运行。一切都通过根目录的 `Makefile` 编排，它会组合 `docker-compose.yml` + `docker-compose.${ENV}.yml`（ENV 为 `dev` 或 `prod`，从 `.env` 读取）。

### 常用命令（在 `CSS_backend-main/` 下运行）

```bash
make            # build + down + migrate + up (full bring-up)
make dev        # run app with uvicorn --reload, port 8000 mounted live
make up / down  # start / stop the stack
make migrate    # alembic upgrade head
make makemigrations message="<msg>"   # autogenerate a migration
make downgrade revision=<rev>          # default -1
make test       # pytest -n logical --reruns 5 (full suite in docker)
make dev_test m=<mark> k=<keyword> o="<pytest args>"   # run a subset / single test
make lint       # pre-commit run --all-files (black, isort, flake8, mypy)
make pre-commit-install
```

通过 `make dev_test k=test_name` 运行单个测试（会把 `-k` 传给 pytest）。`dev`/`dev_test` 下源码是 bind-mount 的，因此改动无需重新构建即可生效。

### 栈中的服务

- `app` — 主 API（gunicorn + uvicorn workers），位于 `nginx` 之后
- `messenger-app` — 独立的 ASGI 应用（`messenger_app.py`），用于聊天/websockets
- `notifications-app` — 独立的 ASGI 应用（`notifications_app.py`），基于 RabbitMQ
- `worker` — `arq` 任务 worker，基于 Redis
- `db`（Postgres）、`redis`、`rabbitmq`、`kafka`（+ `kafka-ui`）、`pgadmin`
- `sms_sender`、`email_sender` — 独立的 Kafka 消费者（各自有 Dockerfile）

### 后端架构（重点部分）

应用位于 `core_app/src/app`，采用**分层、按领域模块化**的结构。三个顶层区域（在 `CSS_backend-main/README.md` 中有说明）：

- `app/internal/` — 应用代码。其中包含：
  - `internal/core/<domain>/` — **领域层**，可在多个应用间复用。每个领域（orders、products、companies、invoices、chats、users、payments 等）都遵循相同的内部拆分：`domains.py`、`dto.py`、`models.py`（SQLAlchemy）、`repositories.py`、`services.py`、`errors.py`、`transport/di.py`（依赖注入接线）。
  - `internal/main_app/<feature>/` — 主 API 的 **HTTP/传输层**。每个 feature 有 `transport/handlers.py`（路由）、`requests.py`、`responses.py`、`docs.py`。`main_app/app.py` 把每个 feature 的路由聚合进 `/api` 路由。
  - `internal/messenger/`、`internal/notifications/`、`internal/worker/` — 其余的 ASGI 应用和任务 worker。
- `app/pkg/` — 面向第三方复用的代码（auth、http、websockets、errors、validators、eden_ai 等）。
- `config/` — 每个关注点一个设置模块（`app_settings.py`、`postgres_settings.py`、`kafka_settings.py` 等）。

**新增端点时应遵循的模式：** 把业务逻辑 + 持久化放进 `internal/core/<domain>/`（service + repository），通过 `internal/main_app/<feature>/transport/handlers.py` 中的路由暴露出来，并在 `main_app/app.py` 中注册该路由。所有 `/api` 路由都受 `check_api_key` 把关（见 `main_app/middlewares/api_key`）。

迁移文件位于 `core_app/src/app/migrations/versions/`（Alembic，约 195 个 revision）。工具链配置在 `pyproject.toml`（black 行宽 120、isort、flake8）和 `mypy.ini` 中。

### Catalog OCR 微服务（`catalog_ocr_service/`）

一个**独立**的 Python 服务（有自己的 `pyproject.toml`、`uv.lock`、`alembic`、Dockerfile），通过 Gemini 做厂商产品目录 OCR。它有自己的 `README.md` 和 `AGENTS.md`——改动它之前先读这两份文档。应用结构：`app/{api,core,db,schemas,services,worker}`。它不属于主 Poetry 项目。

### 其它服务

- `ai_assistant/` — 小型 Node/Express 服务（`server.js`），使用 OpenAI + chartjs。
- `sms_sender/`、`email_sender/` — Python 编写的 Kafka 消费者。

---

## 前端（`CSS_frontend-main/`）

用 Vite 构建的 React 19 SPA。状态管理用 Zustand + TanStack Query；路由用 **TanStack Router**（不是 react-router）；表单用 react-hook-form；表格用 TanStack Table；国际化用 i18next；样式用带生成类型的 SCSS modules。

### 常用命令（在 `CSS_frontend-main/` 下运行）

```bash
npm run dev          # vite (port 3003) + scss-module type generation in watch mode
npm run build        # tsc && vite build
npm run lint         # eslint . --ext ts,tsx --max-warnings 0
npm run lint:fix
npm run stylelint / stylelint:fix
npm run prettier:fix
npm run check:typescript        # tsc, no emit
npm run check:styles-types      # verify generated SCSS module types are current
npm run test         # jest
npm run storybook    # storybook on :6006
npm run plop:cc      # scaffold a new component from _plop-templates
```

`npm run dev` 会把 Vite 与 watch 模式下的 `typed-scss-modules` **并发**运行——`*.module.scss` 文件会生成对应的 `.d.ts` 类型。如果类型报错指向缺失的 SCSS module 类型，运行 `npm run generate-scss-types`。

### 前端架构

- 路径别名（在 `vite.config.ts` 和 `tsconfig.json` 的 `baseUrl: ./src` 中都有配置）：按 `ui/...`、`api/...`、`hooks/...`、`stores/...`、`models/...`、`config/...`、`constants/...`、`utils/...`、`assets/...`、`app/...` 导入——**不要**用相对路径 `../../`。
- `src/ui/` 采用**类 Feature-Sliced-Design** 的分层：`pages/` → `widgets/` → `features/` → `entities/` → `shared/`。共享/可复用组件属于 `entities/` 或 `shared/`；页面专属的 UI 放在 `pages/<Page>/ui/` 下。
- `src/api/` — 每个后端领域一个文件（`orders.ts`、`products.ts`、`clients.ts` 等）；都是很薄的 axios 封装。Axios + auth-refresh 配置在 `src/config/axios/`。
- `src/stores/` — Zustand stores（`userStore`、`modalStore`、`orderFlowStore` 等）。
- 应用组装在 `src/app/`：`App.tsx`（providers + RouterProvider）、`providers/`（含使用 `react-abac` 做基于权限的访问控制的 `AccessControlProvider`）、`constants/router`。

### 前端约定与已知技术债

`CSS_frontend-main/REFACTORING.md` 记录了一份正在进行的重构计划：重复的向导组件（AddClients / UploadProducts / Catalog）、重复的报表表格、应当迁到 `src/models/common/entities.ts` 的重复类型，以及需要拆分的超大 hook 文件。**在这些区域动手之前先查阅它**——优先合并进 `src/ui/entities/`，而不是复制粘贴。跨页面导入（例如 Catalog 从 UploadProducts 导入）被标记为需要修复的坏味道，而不是可以照搬的模式。

---

## 跨项目通用注意事项

- **Git / 分支：** 分支和提交信息都以 YouTrack 任务 ID 为准（例如 `CSS-2: ...`）；后端通过 pre-commit 的 `commit-msg` 钩子强制执行这一点。CI 用的是 GitLab（每个项目里的 `.gitlab-ci.yml`），不是 GitHub Actions。
- **环境：** 每个项目都需要自己的 `.env`（从 `.env.example` 复制）。后端的 `Makefile` 和 Compose 文件会从中读取 `ENV`、`PLATFORM`、镜像名、端口以及所有服务凭证。
