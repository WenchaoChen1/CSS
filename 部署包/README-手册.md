# CSS 部署包（部署源外置版）使用手册

> 生成日期：2026-07-08。核心理念：**前后端项目原样放进 `apps\`，一个字都不用改**；
> 打镜像、多环境 compose 启动、env 配置、EC2 发布，全部由本部署包接管。
> 换新版本代码 = 换 `apps\` 下的两个目录，然后按《换新版本核对清单.md》核对即可。
> 本包取代之前的 `发布包\`（那套脚本依赖项目内的 deploy/ 目录，本包不再需要）。

---

## 一、目录结构

```
部署包\
├── README-手册.md               ← 本文件
├── 换新版本核对清单.md            ← 换代码版本时要核对什么(项目本身零修改)
├── apps\                        ← 【把前后端项目原样放这里】(或用 junction 指向,见目录内说明)
│   ├── CSS_backend-main\
│   └── CSS_frontend-main\
├── compose\
│   ├── dev.yml                  ← 本地全栈(db+全部服务+kafka+senders+pgadmin+可选前端容器)
│   ├── infra.yml                ← AWS 支撑栈: kafka/kafka-ui/redis/rabbitmq/ocr-redis
│   ├── backend.yml              ← AWS 后端栈: app×4/nginx/senders/ai_assistant/OCR(无 db,DB 在 RDS)
│   └── frontend.yml             ← AWS 前端栈: SPA + 同源反代
├── config\
│   └── frontend-nginx.conf      ← 前端容器 nginx(本地与 AWS 共用,反代 /api /ws /notifications)
├── env\                         ← 每环境一个目录: backend.env(运行时) + frontend.env(构建时)
│   ├── dev\    backend.env + frontend.env      (本地,已就绪)
│   ├── test\   backend.env + frontend.env      (AWS test,已就绪,含真实凭证勿提交)
│   └── uat\    backend.env.example + frontend.env.example   (模板)
├── bin\
│   ├── 打镜像推ECR.ps1           ← 需求1: 打镜像(7 个镜像 build + push;自动补建 ECR 仓库)
│   ├── 创建ECR仓库.ps1           ← 单独/预先在目标账号建齐 7 个 ECR 仓库(幂等)
│   ├── 本地dev.ps1               ← 需求2: 本地 dev 环境 compose 启动/运维
│   ├── deploy.sh                 ← 需求2: EC2 端 test/uat/prod 三栈启动/运维
│   ├── 同步部署文件到EC2.ps1      ← EC2 需要的文件一键同步(目标机从 env 读)
│   └── 连接EC2.ps1               ← SSH 到目标环境 EC2(目标机从 env 读)
└── 迁移\                        ← 从 dev 旧组织(021213872872)迁数据到 larry 新组织
    ├── README.md
    ├── 源环境.env.example        ← dev 各环境 SSH + dev/larry AWS profile 配置模板
    ├── 拉取数据库.ps1            ← SSH docker exec pg_dump 拉库到本地
    ├── 拉取docker-env.ps1        ← 采集各容器环境变量 + 磁盘 .env 清单
    └── 拉取S3.ps1               ← dev 账号 S3 下载,可选回推 larry 新桶
```

**多环境 / 多账号可配置性（本次重做重点）**：镜像仓库和部署目标全部参数化到 `env\<env>\backend.env`——
换组织/账号改 `AWS_ACCOUNT_ID`+`AWS_REGION`+`ECR_REGISTRY`(+`AWS_PROFILE` 指向该账号的本地凭证);
test/uat/prod **推不同仓库**改 `ECR_REPO_PREFIX`/`ECR_FRONTEND_PREFIX`(如 `css-prod-backend`);
部署目标机改 `DEPLOY_HOST`/`DEPLOY_USER`/`DEPLOY_KEY`/`DEPLOY_PATH`。脚本一律以 env 文件为准,无硬编码。

**技术要点（为什么项目能零修改）**：
- 所有 compose 的 build context 指向 `apps\` 下的项目目录（compose 统一带 `--project-directory .` 从部署包根运行，脚本已封装）。
- 前端构建用 `dockerfile_inline`（等价原 Dockerfile.novalidate，跳过 tsc），VITE_* env 和 nginx 配置通过 `additional_contexts` 从部署包注入——项目里不需要 `.env`、`Dockerfile.novalidate`、`nginx.aws.conf`。
- ai_assistant 的 Dockerfile 修复（alpine→Debian，解决 canvas/DNS 构建失败）也内联在 `compose/backend.yml`，不改项目文件。
- 要求 Docker Compose v2.17+（支持 dockerfile_inline / additional_contexts；Docker Desktop 与 EC2 现装版本均满足）。

---

## 二、首次准备（一次性）

1. 把项目放进 `apps\`（两个目录名必须是 `CSS_backend-main` / `CSS_frontend-main`）。
   **推荐用目录联接指向工作区里已连 GitHub 的活仓库**（换代码只需在活仓库 `git pull`,部署包自动跟随）：
   ```powershell
   cd C:\github-code\chain-serve\部署包\apps
   # 方式 A(推荐):junction 指向活仓库(本会话已建好,通常无需再执行)
   New-Item -ItemType Junction -Path .\CSS_backend-main  -Target C:\github-code\chain-serve\CSS_backend-main
   New-Item -ItemType Junction -Path .\CSS_frontend-main -Target C:\github-code\chain-serve\CSS_frontend-main
   # 方式 B:复制(占空间,与活仓库脱钩)
   Copy-Item -Recurse C:\github-code\chain-serve\CSS_backend-main  .\CSS_backend-main
   Copy-Item -Recurse C:\github-code\chain-serve\CSS_frontend-main .\CSS_frontend-main
   ```
   > 重建/换指向前先删旧链接：`cmd /c rmdir .\CSS_backend-main`（只删链接,不动源目录）。`apps\` 已被根 `.gitignore` 整体排除。
2. env 已就绪：`env\dev\`、`env\test\` 是从现行真实配置生成的，可直接用。uat/prod 从 example 复制填值。
3. AWS 侧前置（已配好则跳过）：aws cli 凭证（ECR push 权限）、`css-non-prod-key.pem`、EC2 安全组放行本机 IP——细节见 `发布包\发布手册.md` 第一节或 `aws-ops.local.md`。

---

## 三、需求 1：打镜像

```powershell
.\bin\打镜像推ECR.ps1                 # test 环境(默认),tag 取 env\test\backend.env 的 IMAGE_TAG
.\bin\打镜像推ECR.ps1 -EnvName uat
.\bin\打镜像推ECR.ps1 -Tag v1.2.3     # 显式 tag
```

构建并推送 7 个镜像：`css-backend/{app,nginx,sms-sender,email-sender,ai-assistant,catalog-ocr}` + `css-frontend/app`。
脚本自动处理：ECR 登录（cmd /c 包裹规避 PS5.1 管道 400）、自动创建缺失仓库、前端 VITE_* 烤入（取 `env\<env>\frontend.env`）。

**记忆点**：后端代码和前端 VITE_* 都是**烤进镜像**的——改了就要重新打镜像；只有 `backend.env` 是运行时读取，改后 restart 即生效。

## 四、需求 2：docker compose 启动（分环境）

### 本地 dev（`env\dev\backend.env`，本地 Postgres，全容器）

```powershell
.\bin\本地dev.ps1 build      # 首次构建(慢:weasyprint/texlive + poetry)
.\bin\本地dev.ps1 up         # 启动全栈(kafka 是登录硬依赖,已包含)
.\bin\本地dev.ps1 migrate    # alembic upgrade head(目标库=env 的 POSTGRES_DB,当前 css_dev)
.\bin\本地dev.ps1 rebuild    # 改后端代码后:重建 4 个 app 镜像并重启
.\bin\本地dev.ps1 front      # 可选:构建并启动前端容器 http://localhost:3003(零项目修改,无 HMR)
.\bin\本地dev.ps1 [down|ps|logs|restart]
```

- 项目名/容器名/卷名与旧方案完全一致（`css-backend__*`），**原有本地数据库卷自动沿用**，无需迁移数据。
- 验证：`http://localhost:8080/docs`（后端 Swagger）；2FA 码在 `http://localhost:8085` kafka-ui → Topics → sms_send；pgAdmin `:8006`。
- **前端本地开发两种方式**：
  - 零项目修改：`front` 起容器（改代码/改 `env\dev\frontend.env` 后重跑 `front` 重建，约 1-2 分钟，无热更新）；
  - 要 HMR 热更新：只能在项目里跑 `npm run dev`，且需要给项目 `vite.config.ts` 打 dev 反代补丁 + 项目根放 `.env`——这是唯一做不到零修改的场景（vite 反代 /api /ws /notifications 到 :8080,`VITE_API_BASE_URL=/api`,详见前端仓库 `vite.config.ts` 与本项目 `本地运行指南.md`）。

### AWS test / uat / prod（RDS + ECR + EC2 三栈）

```powershell
# 本机:打镜像(见需求1) -> 同步部署文件(首次或 compose/env/deploy.sh 有改动时)
.\bin\同步部署文件到EC2.ps1              # -EnvName uat 换环境
.\bin\连接EC2.ps1
```

EC2 上（文件树根 `/opt/css`，与本包结构一致：`compose/`、`env/<env>/`、`bin/`）：

```bash
cd /opt/css
./bin/deploy.sh test deploy              # 三栈全发(infra->backend->frontend)
./bin/deploy.sh test deploy backend      # 只发后端
./bin/deploy.sh test deploy frontend     # 只发前端
./bin/deploy.sh test migrate             # alembic upgrade head(打 RDS;⚠️先做 RDS 快照)
./bin/deploy.sh test [ps|logs <栈>|restart|down|pytest]
```

三栈是独立 compose 项目（`css-<env>-{infra,backend,frontend}`，共享网络 `css-<env>-net`），项目名与旧方案一致——**从旧 deploy/ 体系切换过来时同名项目直接接管现有容器，不会重复建栈**。验证：前端 `http://100.30.61.207`、后端 `:8080/api/docs`、kafka-ui `:8085`。

## 五、env 文件约定

| 文件 | 读取时机 | 改动后 |
|------|---------|--------|
| `env\<env>\backend.env` | **运行时**（env_file 挂进容器；同时作为 compose 变量插值来源） | 同步(AWS)/直接 `up -d`(本地) + restart 即生效 |
| `env\<env>\frontend.env` | **构建时**（烤进前端静态 JS） | 必须重新打前端镜像再发布 |

三处 key 耦合不变：`API_KEY`(backend.env) == `VITE_X_API_KEY`(frontend.env)；`CATALOG_OCR_API_KEY` == `OCR_API_KEY`。
新建环境：`env\uat\*.example` 复制去掉 `.example` 填真实值；必填变量以 `apps\CSS_backend-main\core_app\src\config\*.py` 的 pydantic 类为准（`CATALOG_OCR_BASE_URL/API_KEY` 无默认值必填）。

## 六、EC2 上需要的文件（全清单）

```
/opt/css/
├── compose/infra.yml + backend.yml + frontend.yml
├── env/<env>/backend.env        (chmod 600)
└── bin/deploy.sh                (LF + chmod +x)
```

就这 5 个文件（`同步部署文件到EC2.ps1` 一键搞定）。EC2 只 pull 镜像不 build，`apps/`、`config/`、`frontend.env` 都不需要上去。旧的 `/opt/css/deploy/` 目录切换后可删除。

## 七、故障排查 / 更多细节

常见故障表（ECR 登录 400、kafka 登录 500、password salt、RDS 密码轮换三处更新等 14 条）见 `C:\github-code\chain-serve\发布包\发布手册.md` 第六节，全部仍然适用（仅文件路径按本包换算：`deploy/.env.test` → `env/test/backend.env`）。从 dev 旧组织迁移数据（DB / docker env / S3）见本包 `迁移\README.md`；数据库快照与 alembic 注意事项见项目根 `CLAUDE.md`。
