# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a **CSS (Chain Serve)** monorepo-style workspace containing two independently-deployed projects plus a database snapshot:

| Path | What it is |
|------|------------|
| `CSS_backend-main/` | Python / FastAPI backend (Poetry, Docker Compose, Alembic) |
| `CSS_frontend-main/` | React 19 + TypeScript + Vite SPA |
| `postgres_backup_20260628.sql` | A ~6.8 MB Postgres dump (snapshot, not loaded automatically) |

The two projects have **separate toolchains, CI pipelines, and `.env` files**. Work on them independently — `cd` into the relevant project before running commands.

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

**`css_dev` data was imported best-effort from `css_dump` via dblink** (`db_compare/import_snapshot_to_css_dev.sql` + `reconcile_*.sql`), copying only columns common to both schemas with FK checks off. Because the schemas diverged, `css_dev` has these **deliberate divergences from the pure code schema** (dev-only):
- `businesstype` enum gained value `MANUFACTURER` (snapshot had it).
- `company.user_id` had its `NOT NULL` dropped (snapshot rows have no owner; that's a code-only user_management column).
- `company_audit_log` is **empty** (its id column is uuid in code but integer in the snapshot — unresolved type divergence).
- The 14 snapshot-only `manufacturer_*` / `payment_method` / `product_attribute*` tables do **not** exist in `css_dev` (no code tables for them), so that data was dropped.

To rebuild `css_dev` from scratch: `DROP DATABASE css_dev; CREATE DATABASE css_dev;` → `alembic upgrade head` (with `-e POSTGRES_DB=css_dev`) → run the three `db_compare/*.sql` scripts in order (`import_snapshot_to_css_dev.sql`, `reconcile_failed_tables.sql`, `reconcile_company.sql`).

Compare the two to discover which migrations are missing from GitHub:
```
docker exec css-backend__db pg_dump -U postgres --schema-only --no-owner postgres  > schema_code.sql
docker exec css-backend__db pg_dump -U postgres --schema-only --no-owner css_dump > schema_dump.sql
```

### `.env` files (already generated)

Both projects need a `.env` (now present, generated from each `.env.example`). Two musts:
- The backend `.env` is a **runtime `env_file`, NOT baked into the image** — editing it needs only a container restart, not a rebuild.
- Backend `API_KEY` **must equal** frontend `VITE_X_API_KEY`, or every request is rejected by the `/api` `check_api_key` guard. The frontend points at `http://localhost:8080` (the backend nginx port = backend `PORT`).
- **`.env.example` is incomplete.** `config/catalog_ocr_settings.py` requires `CATALOG_OCR_BASE_URL` and `CATALOG_OCR_API_KEY` (no defaults), but they are absent from `.env.example`. Missing them raises a pydantic `ValidationError` that blocks boot of **all four** app entrypoints (the shared `Settings` won't instantiate). They are included in the generated `.env`. When sanity-checking env vars, trust the `config/*.py` pydantic classes, not `.env.example`.

### Redeploy after a backend code change

Code IS baked into the image (`COPY src/ .`), so **code** changes need a rebuild (env changes do not). Pass the dev env override `deploy/docker-compose.dev.yml` (it folds in json-file logging, exposed 5432, and a local Kafka — **Kafka is required for auth**: the auth DI eagerly starts a producer against `kafka:9092`, so login 500s without it):
```
docker compose --env-file .env -f core_app/docker-compose.yml -f deploy/docker-compose.dev.yml build app worker messenger-app notifications-app
docker compose --env-file .env -f core_app/docker-compose.yml -f deploy/docker-compose.dev.yml up -d
```
A `redeploy.ps1` at the backend root wraps this. Environments: **dev is local** (`deploy/docker-compose.dev.yml` + `deploy/{windows,linux}/dev.*`); **test / uat / prod deploy to AWS** (EC2 + ECR + RDS + S3) as **three independent compose stacks** — `deploy/docker-compose.{infra,backend,frontend}.yml` (separate projects `css-<env>-{infra,backend,frontend}` sharing docker network `css-<env>-net`, so each deploys independently) — driven by `deploy/aws/{build-push.sh,build-push.ps1,deploy.sh}` (`deploy.sh <env> deploy [stack]`) + per-env `deploy/.env.<env>` (templates: `deploy/.env.<env>.example`). The AWS stacks have **no db/ocr-db/pgadmin containers** (Postgres lives in RDS: databases `css_<env>` + `ocr_<env>`). The frontend image bakes `VITE_*` from `CSS_frontend-main/.env.<env>` at **build time** (uses `Dockerfile.novalidate` — tsc currently fails on 16 pre-existing type errors). The old root `docker-compose.{dev,test,prod}.yml` and `deploy/docker-compose.prod.yml` + old test/prod scripts were removed (2026-07-06); the `Makefile` now composes only the root `docker-compose.yml`. See `deploy/README.md`.

### Windows host notes

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
