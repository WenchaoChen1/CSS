# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a **CSS (Chain Serve)** monorepo-style workspace containing two independently-deployed projects plus a database snapshot:

| Path | What it is |
|------|------------|
| `CSS_backend-main/` | Python / FastAPI backend (Poetry, Docker Compose, Alembic) |
| `CSS_frontend-main/` | React 19 + TypeScript + Vite SPA |
| `备份/` | 数据库/S3/docker-env 迁移产物（含旧快照，gitignore；原根目录 postgres_backup_20260628.sql 已归档移除） |

The two projects have **separate toolchains, CI pipelines, and `.env` files**. Work on them independently — `cd` into the relevant project before running commands.

---

## 环境 → AWS 账号映射（重要，先读）

本项目有**两个 AWS 账号**，六个环境按名称固定归属，**切勿混淆**：

| 环境 | AWS 账号 | 区域 | 角色 |
|------|----------|------|------|
| `staging` / `dev` / `preprod` | **老账号 `021213872872`** | eu-central-1 | 原团队遗留环境（全容器、无 RDS）→ **数据迁移的来源** |
| `test` / `uat` / `prod` | **新账号 larry `582797602427`** | us-east-1 | 我方新建环境（EC2 + ECR + RDS + S3）→ **部署目标** |

- **老账号（迁移源）**：只有 `preprod`(3.74.51.100) 已开通 SSH；`dev`/`staging` 待开通。用 `docs/老aws账号/` 的脚本把 DB / docker env / S3 拉到本机 `备份/`。
- **新账号（部署目标，2026-07-29 实查）**：旧默认 VPC 的 test 机已删除，全部资源在新 VPC。网关机 `css-non-prod-gw`(i-08b0ef319d08eae38, EIP 3.225.148.166, **只剩堡垒 SSH + NAT 出网**，nginx 反代已停用)；应用机 `css-test-app`(10.20.10.10, m7i-flex.large, **三栈已部署可用**) 与 `css-uat-app`(10.20.11.10, **只建机未部署**)；prod 应用机待 Paid plan。RDS `css-non-prod`(PG16.14, db.t4g.micro, 私有子网, test+uat 共用；库 `css-test-main`/`css-test-ocr` 已载入 preprod 数据并**已脱敏**——邮箱前缀 1、口令统一 `Test1234!`)；css-prod 实例等 Paid plan。入口：**每环境一个 ALB**（`css-test`/`css-uat`/`css-prod`）。**资源命名一律 `css-non-prod-*` / `css-prod-*`（带连字符）**。CloudWatch 监控 test/uat 已配（各 9 告警+Dashboard，SNS 暂无订阅者）；RDS 升配 db.t4g.small 与 css-prod 实例均被 Free plan 拦截；本地开发直传 S3 走桶 `css-dev-582797602427` + 用户 `css-app-dev`（key 在 deploy-env/dev）。运维凭证与命令全集见工作区 `运维访问速查.local.md`（gitignore）。
- 脚本按账号分放（2026-07-28）：`docs/环境运维执行脚本/`=新账号资源创建/推镜像（01-vpc~10），`docs/老aws账号/`=老账号数据拉取；**`部署包/` 已整体退役并入 `CSS_backend-main/deploy/`**（compose 编排、本地 dev、EC2 端 deploy.sh；env 配置 2026-07-28 再迁出到工作区根 `deploy-env/`）；CI/CD 已落新组织两仓库（`.github/workflows/cicd.yml`），手册在 `docs/环境运维执行脚本/`（总流程在其 README，组件手册在 08/09 文件夹）。

---

## Project handover status (read first)

This codebase is being **taken over from another team**. Critical context that is NOT obvious from the code:

- **Only `main` (from GitHub) is available.** The other team's active dev work lived in **GitLab and was never pushed to GitHub**, so the code here may lag behind their real dev environment.
- **The DB snapshot is newer than the code.** `postgres_backup_20260628.sql` (2026-06-28) is ~2.5 months ahead of `main` (latest migration `2026_04_10`, revision `c868e4eb8b15`). Its `alembic_version` very likely points at revisions that **do not exist** in `migrations/versions/` here — do **not** run `alembic upgrade/downgrade` against the imported snapshot.
- **The snapshot is binary (`pg_dump -Fc`), despite the `.sql` extension** (file header `PGDMP`). Restore with `pg_restore`, NOT `psql`.

### Local databases (three, in the one container `css-backend__db`)

| Database | Source | Used by |
|----------|--------|---------|
| `css_dev` | `alembic upgrade head` + **best-effort snapshot data import** | **the app (working DB, `POSTGRES_DB=css_dev`)** |
| `postgres` | clean `alembic upgrade head`, empty | clean code-schema baseline / reference |
| `css_dump` | raw restored snapshot (`pg_restore`) | schema & data comparison — app does **not** connect here |

The app/alembic target whichever DB `POSTGRES_DB` names (see `config/postgres_settings.py`; `migrations/env.py` reuses the same settings), so alembic only ever touches the named DB. Postgres is exposed on host `localhost:5432` (postgres/postgres) via the Windows override.

**`css_dev` data was imported best-effort from `css_dump` via dblink**（原 `db_compare/` 调和脚本，**该目录已于 2026-07-28 删除**——main 已是 preprod 代码，旧 css_dev 调和流程作废）, copying only columns common to both schemas with FK checks off. Because the schemas diverged, `css_dev` has these **deliberate divergences from the pure code schema** (dev-only):
- `businesstype` enum gained value `MANUFACTURER` (snapshot had it).
- `company.user_id` had its `NOT NULL` dropped (snapshot rows have no owner; that's a code-only user_management column).
- `company_audit_log` is **empty** (its id column is uuid in code but integer in the snapshot — unresolved type divergence).
- The 14 snapshot-only `manufacturer_*` / `payment_method` / `product_attribute*` tables do **not** exist in `css_dev` (no code tables for them), so that data was dropped.

~~To rebuild `css_dev` from scratch via `db_compare/*.sql`~~ **已作废（2026-07-28）**：`db_compare/` 已删除；旧 css_dev 对应旧代码线，勿在其上跑新迁移。开发库以 preprod 备份恢复或空库 `alembic upgrade head` 重建（见 `备份/数据库/`）。

Compare the two to discover which migrations are missing from GitHub:
```
docker exec css-backend__db pg_dump -U postgres --schema-only --no-owner postgres  > schema_code.sql
docker exec css-backend__db pg_dump -U postgres --schema-only --no-owner css_dump > schema_dump.sql
```

### `.env` files（⚠️ 上游遗留模型说明——本地 dev 已改走工作区 `deploy-env/dev/backend.env` + `本地dev.ps1`，本节仅供参照上游 Makefile 流程）

Both projects need a `.env` (now present, generated from each `.env.example`). Two musts:
- The backend `.env` is a **runtime `env_file`, NOT baked into the image** — editing it needs only a container restart, not a rebuild.
- Backend `API_KEY` **must equal** frontend `VITE_X_API_KEY`, or every request is rejected by the `/api` `check_api_key` guard. The frontend points at `http://localhost:8080` (the backend nginx port = backend `PORT`).
- **`.env.example` is incomplete.** `config/catalog_ocr_settings.py` requires `CATALOG_OCR_BASE_URL` and `CATALOG_OCR_API_KEY` (no defaults), but they are absent from `.env.example`. Missing them raises a pydantic `ValidationError` that blocks boot of **all four** app entrypoints (the shared `Settings` won't instantiate). They are included in the generated `.env`. When sanity-checking env vars, trust the `config/*.py` pydantic classes, not `.env.example`.

### Redeploy after a backend code change

Code IS baked into the image (`COPY src/ .`), so **code** changes need a rebuild (env changes do not). 本地 dev（2026-07-28 统一模型）：栈=`deploy/compose/dev.yml`（含本地 Postgres/kafka/kafka-ui/pgadmin——**Kafka is required for auth**: the auth DI eagerly starts a producer against `kafka:9092`, so login 500s without it），配置=工作区根 `deploy-env/dev/backend.env`（2026-07-28 env 整体迁出仓库），入口：
```
.\deploy\windows\本地dev.ps1 [up|down|build|rebuild|migrate|ps|logs|restart|front]
```
仓库根 `redeploy.ps1` 是它的薄封装（rebuild）。**test / uat / prod 走 CI/CD**（GitHub Actions → ECR 双 tag `<env>-vN` 版本号+`<env>` 浮动，lifecycle 保 5 → 部署暂为手动 `docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh`），编排=`deploy/compose/{infra,backend,frontend}.yml`（独立项目 `css-<env>-*` 共享网络 `css-<env>-net`），运行时配置唯一事实源=SSM Parameter Store `/css/<env>/backend.env`（deploy.sh 自动渲染；本地底稿在工作区 `deploy-env/<env>/`）。AWS 栈无 db/pgadmin 容器（Postgres 在 RDS；新库名规范 `css-<env>-main`/`css-<env>-ocr`）。前端镜像构建期烤入 `VITE_*`（来自 `/css/<env>/frontend.env`，用 `Dockerfile.novalidate`——tsc 尚有 16 个存量类型错误）。手册见工作区 `docs/环境运维执行脚本/`（README 总流程 + 08/09 组件手册）；deploy 结构见 `deploy/README.md`。

### Windows host notes（同上：core_app compose + 根 .env 属上游遗留模型，本地 dev 一律走 deploy/windows/本地dev.ps1）

No `make` / `pg_restore` / `sudo` on the host (Docker Desktop only). Use `docker compose` native commands — the `Makefile` is Linux-only (its `makemigrations` / `poetry_*` targets call `sudo chown` and will not run here). Run compose from `CSS_backend-main/` and pass `--env-file .env` so `${VAR}` interpolation resolves (the core stack lives in `core_app/docker-compose.yml`; the root `docker-compose.yml` additionally `include`s the OCR + ai_assistant services, which need extra API keys).

---

## Backend (`CSS_backend-main/`)

FastAPI app run as a multi-service Docker Compose stack. Everything is orchestrated through the root `Makefile`, which composes `docker-compose.yml` + `docker-compose.${ENV}.yml` (ENV is `dev` or `prod`, read from `.env`).

### Common commands (run from `CSS_backend-main/`)

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

Run a single test via `make dev_test k=test_name` (passes `-k` to pytest). Source is bind-mounted for `dev`/`dev_test` so changes are picked up without rebuilding.

### Services in the stack

- `app` — main API (gunicorn + uvicorn workers), behind `nginx`
- `messenger-app` — separate ASGI app (`messenger_app.py`) for chats/websockets
- `notifications-app` — separate ASGI app (`notifications_app.py`), RabbitMQ-backed
- `worker` — `arq` task worker, Redis-backed
- `db` (Postgres), `redis`, `rabbitmq`, `kafka` (+ `kafka-ui`), `pgadmin`
- `sms_sender`, `email_sender` — standalone Kafka consumers (own Dockerfiles)

### Backend architecture (the important part)

The app lives in `core_app/src/app` and uses a **layered, domain-modular** structure. Three top-level zones (documented in `CSS_backend-main/README.md`):

- `app/internal/` — application code. Within it:
  - `internal/core/<domain>/` — the **domain layer**, reusable across apps. Each domain (orders, products, companies, invoices, chats, users, payments, …) follows the same internal split: `domains.py`, `dto.py`, `models.py` (SQLAlchemy), `repositories.py`, `services.py`, `errors.py`, `transport/di.py` (dependency injection wiring).
  - `internal/main_app/<feature>/` — the **HTTP/transport layer** for the main API. Each feature has `transport/handlers.py` (the router), `requests.py`, `responses.py`, `docs.py`. `main_app/app.py` aggregates every feature router into the `/api` router.
  - `internal/messenger/`, `internal/notifications/`, `internal/worker/` — the other ASGI apps and the task worker.
- `app/pkg/` — code intended to be reusable by third parties (auth, http, websockets, errors, validators, eden_ai, etc.).
- `config/` — one settings module per concern (`app_settings.py`, `postgres_settings.py`, `kafka_settings.py`, …).

**Pattern to follow when adding an endpoint:** put business logic + persistence in `internal/core/<domain>/` (service + repository), expose it via a router in `internal/main_app/<feature>/transport/handlers.py`, and register that router in `main_app/app.py`. All `/api` routes are gated by `check_api_key` (see `main_app/middlewares/api_key`).

Migrations live in `core_app/src/app/migrations/versions/` (Alembic, ~195 revisions). Tooling config is in `pyproject.toml` (black line-length 120, isort, flake8) and `mypy.ini`.

### Catalog OCR microservice (`catalog_ocr_service/`)

A **separate** standalone Python service (its own `pyproject.toml`, `uv.lock`, `alembic`, Dockerfile) for manufacturer catalog OCR via Gemini. Has its own `README.md` and `AGENTS.md` — read those before touching it. App layout: `app/{api,core,db,schemas,services,worker}`. Not part of the main Poetry project.

### Other services

- `ai_assistant/` — small Node/Express service (`server.js`) using OpenAI + chartjs.
- `sms_sender/`, `email_sender/` — Python Kafka consumers.

---

## Frontend (`CSS_frontend-main/`)

React 19 SPA built with Vite. State via Zustand + TanStack Query; routing via **TanStack Router** (not react-router); forms via react-hook-form; tables via TanStack Table; i18n via i18next; styling via SCSS modules with generated types.

### Common commands (run from `CSS_frontend-main/`)

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

`npm run dev` runs Vite **concurrently** with `typed-scss-modules` in watch mode — `*.module.scss` files generate matching `.d.ts` types. If type errors reference missing SCSS module types, run `npm run generate-scss-types`.

### Frontend architecture

- Path aliases (configured in both `vite.config.ts` and `tsconfig.json` `baseUrl: ./src`): import as `ui/...`, `api/...`, `hooks/...`, `stores/...`, `models/...`, `config/...`, `constants/...`, `utils/...`, `assets/...`, `app/...` — **not** relative `../../`.
- `src/ui/` follows a **Feature-Sliced-Design-like** layering: `pages/` → `widgets/` → `features/` → `entities/` → `shared/`. Shared/reusable components belong in `entities/` or `shared/`; page-specific UI lives under `pages/<Page>/ui/`.
- `src/api/` — one file per backend domain (`orders.ts`, `products.ts`, `clients.ts`, …); thin axios wrappers. Axios + auth-refresh config lives in `src/config/axios/`.
- `src/stores/` — Zustand stores (`userStore`, `modalStore`, `orderFlowStore`, …).
- App composition in `src/app/`: `App.tsx` (providers + RouterProvider), `providers/` (incl. `AccessControlProvider` using `react-abac` for permission-based access control), `constants/router`.

### Frontend conventions & known debt

`CSS_frontend-main/REFACTORING.md` documents an active refactoring plan: duplicated wizard components (AddClients / UploadProducts / Catalog), duplicated report tables, duplicated types that should move to `src/models/common/entities.ts`, and oversized hook files to split. **Consult it before working in those areas** — prefer consolidating into `src/ui/entities/` over copying. Cross-page imports (e.g. Catalog importing from UploadProducts) are flagged as smells to fix, not patterns to imitate.

---

## Cross-cutting notes

- **Git / branches:** branches and commit messages are keyed to YouTrack task IDs (e.g. `CSS-2: ...`); the backend enforces this via a pre-commit `commit-msg` hook. CI is GitLab (`.gitlab-ci.yml` in each project), not GitHub Actions.
- **Environments:** each project needs its own `.env` (copy from `.env.example`). The backend's `Makefile` and Compose files read `ENV`, `PLATFORM`, image names, ports, and all service credentials from it.
