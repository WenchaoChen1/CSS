# 02 · preprod 用什么部署 · 脚本是什么

> 仅描述客户 **preprod**（3.74.51.100）的真实部署方式，以 SSH 实测 + 仓库脚本核对为准。

---

## 一、一句话概括

**GitLab CI/CD 触发 → 在 preprod EC2 上的自托管 gitlab-runner 里，跑 `make` 目标 → `make` 展开为 `docker compose`，从 GHCR 拉镜像、迁移数据库、拉起容器。** 服务器磁盘上不留部署文件/`.env`（job 结束即清理）。

```
push 到分支 deployment/preprod
        │
        ▼  GitLab 流水线（.gitlab-ci.yml），3 个 stage
   build.preprod  →  test.preprod  →  deploy.preprod(手动触发)
        │
        ▼  由 preprod EC2 上的 gitlab-runner 执行（runner tag = job:*.preprod）
   before_script: docker login GHCR + cp $DOT_ENV .env
   deploy 命令:   make pull all
        │
        ▼  gitlab-runner 挂宿主 docker.sock → 操作宿主 Docker
   docker compose -f docker-compose.yml -f docker-compose.prod.yml <pull|build|down|migrate|up>
        │
        ▼  拉起 20+ 容器（app/db/redis/nginx/worker/messenger/notifications + kafka/kafka-ui/pgadmin/sms/email + OCR 整套）
```

---

## 二、部署脚本逐层拆解

### 1) `.gitlab-ci.yml`（流水线定义）

- 镜像 `docker:27-cli`；stage 顺序 `build → test → deploy`。
- 每个环境一组 job，按分支触发：`deployment/dev|test|preprod|prod`。preprod 的三个 job：
  - `build.preprod`（push 自动）：`make build push`
  - `test.preprod`（push 自动）：`make pull test`
  - `deploy.preprod`（**when: manual，需手动点**）：`make pull all`
- `before_script`（每个 job 前）：
  ```sh
  apk add make
  docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY   # 登录 GHCR
  cp $DOT_ENV $(pwd)/.env                                                   # 从 GitLab 文件变量还原 .env
  ```
  > 即 **`.env` 来自 GitLab CI/CD 的 File 类型变量 `$DOT_ENV`**，镜像仓库凭据来自 `$CI_REGISTRY*` 变量。

### 2) `Makefile`（实际命令）

```makefile
-include .env
RUN_DOCKER_COMPOSE = docker compose -f docker-compose${PLATFORM}.yml -f docker-compose.${ENV}.yml

all:     build down migrate up      # 关键：先 build，再 down(停旧)，再 migrate，再 up
pull:    $(RUN) pull
build:   $(RUN) build
up:      $(RUN) up -d
down:    $(RUN) down
migrate: $(RUN) run --rm app bash -c 'alembic upgrade head'
test:    docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm app pytest -n logical --reruns 5
```

- preprod 上 `PLATFORM` 为空、`ENV=prod`（preprod 环境**复用 prod 的 compose 叠加**，没有单独的 `docker-compose.preprod.yml`），所以 `RUN_DOCKER_COMPOSE` 实际是：
  ```
  docker compose -f docker-compose.yml -f docker-compose.prod.yml
  ```
  （与 preprod 容器 label 实测的 `docker-compose.yml,docker-compose.prod.yml` 一致。）
- 因此 **`make pull all`** = `pull`（拉 GHCR 镜像）→ `all`（`build → down → migrate → up -d`）。**每次部署都会 `down` 停服 + `alembic upgrade head` 迁移 + 重新 `up`。**

### 3) `docker-compose.yml`（base）+ `docker-compose.prod.yml`（叠加层）

- base：`app / db(容器 Postgres) / redis / nginx / worker / messenger-app / notifications-app`。
- prod 叠加：`kafka`(KRaft，带卷)、`kafka-ui`(发布 `${KAFKA_UI_PORT}`=8005)、`sms_sender`、`email_sender`、`pgadmin`(发布 `${PGADMIN_PORT}`=8006)。
- 所有服务 `env_file: .env`（把上一步还原的 `.env` 整体注入容器）。

---

## 三、镜像仓库

- **GHCR**：`ghcr.io/igornaumov1337/css-backend__app:preprod-<sha>`、`…css-backend_nginx`、`…css-backend_db` 等（CI 变量 `$CI_REGISTRY/$CI_REGISTRY_USER` 指向 GHCR 个人账号）。
- `registry.devteam.space/docker/kafka:0.0.1`（私有 registry 的 kafka）。
- Docker Hub：redis / rabbitmq / postgres / kafka-ui / pgadmin / gitlab-runner。

---

## 四、runner 与"服务器上有什么"

- preprod EC2 上跑 `gitlab-runner` 容器（compose 项目 `dt-gitlab-runner`，配置在宿主 `/dt/dt-gitlab-runner/config`），**挂载宿主 `/var/run/docker.sock`**，用 runner tag（`job:deploy.preprod` 等）领取本环境的 job，在其构建目录 `/builds/css_new/css-backend` 内执行上面的 `make`。
- **构建目录随 job 清理** → EC2 磁盘上不留 `.env`/compose；运行中容器已把 `.env` 值固化进环境（app 容器实测 117 个变量，见 [05](05-环境变量与密钥审计.md)）。

---

## 五、部署方式的问题

| 级别 | 问题 |
|------|------|
| 🟠 HIGH | **每次部署都 `down` 再 `up` → 有停机窗口**（非零停机/蓝绿）；且 `migrate` 每次自动跑 `alembic upgrade head`，迁移失败会卡住发布。 |
| 🟠 HIGH | **runner 挂 `docker.sock`**：CI 作业等于对宿主机 root 级控制，流水线/runner 被投毒即可接管整台 EC2。 |
| 🟠 HIGH | **主镜像托管在个人 GHCR 账号**（igornaumov1337）：账号丢失/离职即断供，镜像可信度与拉取权限不受团队控制。 |
| 🟠 HIGH | **管理台随 prod 叠加层发布且安全组全开**：pgadmin(8006)/kafka-ui(8005) 端口既 `ports:` 发布、安全组又对 `0.0.0.0/0` 开放 → 公网可直达（见 [01](01-AWS基础设施与EC2清单.md) 第三节）。 |
| 🟡 MEDIUM | **完整 `.env`（全部密钥）注入第三方镜像** kafka-ui / pgadmin（`env_file: .env`），扩大密钥暴露面。 |
| 🟡 MEDIUM | **kafka-ui 认证配置可疑**：`AUTH_TYPE="LOGIN_FORM"` 带引号，易被解析成非预期值导致免认证。 |
| 🟡 MEDIUM | **环境命名混乱**：preprod 环境实际 `ENV=prod`、用 `docker-compose.prod.yml`，没有独立 preprod 叠加 → 配置区分度低，易误发。 |
| 🟡 MEDIUM | **构建目录用完即删** → 服务器上无法本地复现/回滚，出问题只能重跑流水线；无回滚 tag 机制。 |
| 🟡 MEDIUM | **`.env` 经 CI File 变量 + `cp` 落盘再注入**，且前端 CI 曾把 `.env` 打印进 job 日志（见 [04](04-代码审计发现清单.md) fe:.gitlab-ci）。 |

---

## 六、建议

1. 部署改**滚动/蓝绿**，避免 `down` 停机；`migrate` 与发布解耦、加失败回滚。
2. runner 改用 DinD 或独立部署账号，勿直接挂宿主 `docker.sock`。
3. 主镜像迁到**组织级 registry**，停用个人账号托管。
4. pgadmin/kafka-ui 不再发布公网端口 + 安全组收敛（配合 [01](01-AWS基础设施与EC2清单.md) 建议）。
5. 密钥不进第三方镜像、不进 CI 日志；`.env` 走 masked/protected 变量与运行时挂载。
6. 给 preprod 建独立 compose 叠加与命名，消除"preprod 实为 prod"的混淆。
