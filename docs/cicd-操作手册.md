# CI/CD 日常操作手册

> 📍 2026-07-31 自 docs/环境/ 迁入本目录。

> 2026-07-31 更新；§7 为剩余待办。
> 方案原理见 [云服务搭建部署方案/03-CICD-GitHub-Actions.md](云服务搭建部署方案/03-CICD-GitHub-Actions.md)。
> **现状**：push `test`/`uat` 分支 = 全自动（构建 → migrate → SSM 部署）；push `main` 只构建镜像，
> prod 部署走 Actions 手动 Run workflow。部署按 `tag:Environment` 定位目标机。
> CI 用的 OIDC 身份提供方与 `css-deploy-*` 三角色已集中由 `css-terraform` 的 `css-github` stack 管理
> （角色名/ARN 未变，workflow 无需改动）。

## 1. 发布代码

| 目标 | 操作 |
|------|------|
| 同步老仓库代码 | `git fetch origin && git checkout upstream-sync && git merge origin/main`（先跑防重写检查 `git merge-base --is-ancestor HEAD origin/main`）→ 解冲突 → `git push` → 验证无误后 `git checkout test && git merge upstream-sync && git push` |
| 发 test | `git checkout test && git merge ops && git push origin test`——全自动 |
| 发 uat | `git checkout uat && git merge ops && git push origin uat`——全自动（迁移前自动快照） |
| 发 prod | `ops` → `main` 走 PR 合并 → `git push origin main`（自动构建镜像，**不自动部署**）→ Actions → CICD → **Run workflow**（environment=prod，image_tag 留空=重新构建并部署）手动触发部署——这一步就是人工闸（GitHub Free 私有仓库**没有**环境审批闸） |

> ⚠️ **不存在"test → uat → main 逐级晋级"**（2026-08-22 分支重建后）：
> `uat` = main + ops；`test` = main + ops + **support-demo**（老团队线）。
> **绝不能从 test 合并到 uat** —— 那会把 uat 的 alembic 头从 `b3d9f1a2c4e5` 变成 `e8f2a4b6c1d3`。
> 三个环境分支一律**从 `ops` 合入**，prod 由 `ops` → `main` 走 PR。

## 2. 回滚

Actions → 对应仓库的 `cicd` workflow → Run workflow → 选环境 + 填上一个好版本的镜像 tag（`<env>-vN`，如 `test-v12`；手动推送产物为 `<env>-manual-<sha7>`）。手动兜底：`docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh <env> all <tag>`。

## 3. 改环境变量

1. 改 SSM Parameter Store：`/css/<env>/backend.env`（运行时）或 `/css/<env>/frontend.env`（构建期 VITE_*）。
   推荐走 `docs/环境运维执行脚本/11-parameter-store/put-params.sh <env>`（本地底稿在工作区 `deploy-env/<env>/`）；
   Terraform 只管参数**壳**，任何推送方式都不会产生 drift（但**别改壳属性** tier/key_id）；
2. 后端变量：重新部署即生效（不重构建镜像；`deploy-env.sh <env> core` 或重推分支）；前端 VITE_ 变量：需重跑 build 再部署（构建期烤入）；
3. `API_KEY`/`VITE_X_API_KEY`、`CATALOG_OCR_API_KEY`/`OCR_API_KEY` 两对耦合键改动必须同步改两处——CI 有一致性校验兜底，不一致会 fail。

## 4. 查问题

- 流水线失败：看 GitHub Actions 红叉停在哪个 job；
- 部署后服务异常：经堡垒机（`css-non-prod-bastion`，3.225.148.166）SSH 上机 `./deploy.sh <env> ps` / `logs <stack>`，
  或免 SSH 直接 `docs/环境运维执行脚本/09-远程执行与手动部署/run.sh <env> '<命令>'`；
- 2FA 验证码：kafka-ui，走开发入口 ALB `css-non-prod-entry-1482605872.us-east-1.elb.amazonaws.com`
  （test `:8085` / uat `:8086`，仅白名单 IP）。

## 5. 已落地组件（2026-07-31）

| 组件 | 位置 |
|------|------|
| Backend workflow | `Chain-Service-Solutions-Backend` → `.github/workflows/cicd.yml`（lint → 6 镜像双 tag `<env>-vN`+`<env>` → migrate[uat/prod 先打 RDS 快照] → SSM 部署 infra+backend） |
| Frontend workflow | `Chain-Service-Solutions-Frontend` → `.github/workflows/cicd.yml`（eslint → jest/tsc 观察 → VITE 从 Parameter Store 注入构建 → SSM 部署 frontend） |
| 部署 bundle | backend 仓库 `deploy/{compose,config,bin}`（env 本地底稿在工作区根 `deploy-env/<env>/`）；部署时上传到 EC2 `/opt/css-cicd/` |
| 手动部署脚本（兜底） | `docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh <env>`（CI 之外随时可用） |
| deploy.sh 增强版 | `deploy/bin/deploy.sh`：Parameter Store 渲染 env / 镜像 tag 覆盖 / 冒烟 / prune / .last_good |
| SSM 执行器 | `deploy/aws/ssm-run.sh`（按 **`Environment`** 标签定位实例——2026-07-30 由旧 `CssEnv` 键切换，轮询回显结果） |
| CI 用 IAM | OIDC 提供方 + `css-deploy-{test,uat,prod}` 角色 = `css-terraform` 的 `css-github` stack（角色名/ARN 未变） |
| 参数 | `/css/<env>/{backend,frontend}.env` **六个 AWS 环境共 12 个参数均已灌入并在用**（test/uat/prod/support-ref/support-demo/support-sync；2026-08-22 实查。dev 只在本机跑，不入 SSM）。改值走 `put-params.sh <env>` |

## 6. 一次性 GitHub 配置（两仓库都要，未配置前 workflow 会在 AWS 凭证步失败）

1. ~~Repository variables~~ **已免配**（2026-07-28 起角色 ARN/ECR 地址写死于 workflow）。
2. ~~Environments 审批~~ **GitHub Free 私有仓库不支持环境审批**——生产闸改为 workflow 内置手动触发（push main 只构建；部署 prod = Actions → Run workflow）。Environments 用 `test` / `uat` / **`main`** 三个（2026-07-29 起环境名与分支名一律相同，生产环境就叫 `main`，不再用 `production`），三个都已存在、**里面什么都不用填**。
3. charles221900 账号 **Settings → Emails** 验证 `charles@shinypathway.com`（提交头像关联）。

## 7. 待办 / 已知限制

- [ ] 后端 pytest job（需整套 compose + CI 占位 env，阶段二接入）
- [ ] 前端 jest / tsc 目前 `continue-on-error`（观察模式），首轮全绿后转阻断
- [x] ~~**uat 首次部署**~~ 已完成（uat 环境在跑；库=2026-08-22 preprod 备份，alembic 头 `b3d9f1a2c4e5`）
- [x] ~~prod 等 Paid plan 开闸~~ 已完成（2026-08-07 建成三栈，2026-08-22 完成产品正式切换，域名 `chain-serve.com`）
- [ ] 构建缓存（buildx gha cache）与镜像构建提速
