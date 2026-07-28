# CI/CD 日常操作手册

> 已随 CI/CD 落地更新（2026-07-28）；§7 为剩余待办。
> 方案原理见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md)。
> ⚠️ **现阶段（2026-07-28）：CI 只推镜像**——workflow 中的 migrate/deploy job 已注释；部署 = 手动执行 `docs/新aws账号/09-ssm-run-command/deploy-env.sh <env>`。下文的自动部署描述为恢复注释后的目标态。

## 1. 发布代码

| 目标 | 操作 |
|------|------|
| 同步老仓库代码 | `git fetch origin && git checkout upstream-sync && git merge origin/main`（先跑防重写检查 `git merge-base --is-ancestor HEAD origin/main`）→ 解冲突 → `git push` → 验证无误后 `git checkout test && git merge upstream-sync && git push` |
| 发 test | `git push neworg test`——全自动 |
| 发 uat | `git checkout uat && git merge test && git push neworg uat`——全自动（迁移前自动快照） |
| 发 prod | `git checkout main && git merge uat && git push neworg main`（自动构建镜像，**不自动部署**）→ Actions → CICD → **Run workflow**（environment=prod）手动触发部署——这一步就是人工闸（GitHub Free 无环境审批的替代方案） |

## 2. 回滚

Actions → 对应仓库的 `cicd` workflow → Run workflow → 选环境 + 填上一个好版本的镜像 tag（`<env>-vN`，如 `test-v12`；手动推送产物为 `<env>-manual-<sha7>`）→ prod 需再过一次审批。（现阶段部署 job 已注释：回滚 = 手动 `deploy-env.sh <env>` 指定旧 tag。）

## 3. 改环境变量

1. 改 SSM Parameter Store：`/css/<env>/backend.env`（运行时）或 `/css/<env>/frontend.env`（构建期 VITE_*）；
2. 后端变量：重新部署即生效（不重构建镜像；现阶段 = 手动 `deploy-env.sh <env>`）；前端 VITE_ 变量：需重跑 build 再部署（构建期烤入）；
3. `API_KEY`/`VITE_X_API_KEY`、`CATALOG_OCR_API_KEY`/`OCR_API_KEY` 两对耦合键改动必须同步改两处——CI 有一致性校验兜底，不一致会 fail。

## 4. 查问题

- 流水线失败：看 GitHub Actions 红叉停在哪个 job；
- 部署后服务异常：经堡垒机 SSH 上机 `./deploy.sh <env> ps` / `logs <stack>`；
- 2FA 验证码：kafka-ui（SSH 隧道 8085）。

## 5. 已落地组件（2026-07-28）

| 组件 | 位置 |
|------|------|
| Backend workflow | `Chain-Service-Solutions-Backend` → `.github/workflows/cicd.yml`（lint → 6 镜像双 tag `<env>-vN`+`<env>` → ~~migrate[uat/prod 先快照] → SSM 部署 infra+backend~~ **已注释，恢复后生效**） |
| Frontend workflow | `Chain-Service-Solutions-Frontend` → `.github/workflows/cicd.yml`（eslint → jest/tsc 观察 → VITE 从 Parameter Store 注入构建 → ~~SSM 部署 frontend~~ **已注释**） |
| 部署 bundle | backend 仓库 `deploy/{compose,config,bin}`（env 本地底稿已迁工作区根 `deploy-env/<env>/`）；部署时上传到 EC2 `/opt/css-cicd/` |
| 手动部署脚本 | `docs/新aws账号/09-ssm-run-command/deploy-env.sh <env>`（现阶段唯一部署入口） |
| deploy.sh 增强版 | `deploy/bin/deploy.sh`：Parameter Store 渲染 env / 镜像 tag 覆盖 / 冒烟 / prune / .last_good |
| SSM 执行器 | `deploy/aws/ssm-run.sh`（按 `CssEnv` 标签定位实例，轮询回显结果） |
| 参数 | `/css/test/backend.env`（Advanced）+ `/css/test/frontend.env`（✅ 已灌入；uat/prod 待环境建成后灌） |

## 6. 一次性 GitHub 配置（两仓库都要，未配置前 workflow 会在 AWS 凭证步失败）

1. ~~Repository variables~~ **已免配**（2026-07-28 起角色 ARN/ECR 地址写死于 workflow）。
2. ~~Environments 审批~~ **GitHub Free 私有仓库不支持环境审批**——生产闸改为 workflow 内置手动触发（push main 只构建；部署 prod = Actions → Run workflow）。环境无需任何配置；误建的 `main` 环境可删。
3. charles221900 账号 **Settings → Emails** 验证 `charles@shinypathway.com`（提交头像关联）。

## 7. 待办 / 已知限制

- [ ] 后端 pytest job（需整套 compose + CI 占位 env，阶段二接入）
- [ ] 前端 jest / tsc 目前 `continue-on-error`（观察模式），首轮全绿后转阻断
- [ ] 首次端到端验证：配好 §6 → 手动 Rerun 或空提交推 `test` → 全绿后把 CI 提交晋级 uat/main
- [ ] **恢复 workflow 中已注释的 migrate/deploy job**（应用机建成、手动链路验证后转回自动部署）
- [ ] uat/prod：建应用机（06-ec2；RDS `css-non-prod` ✅ 已建成，`css-prod` 等 Paid plan 升级）→ 灌 `/css/{uat,prod}/*` 参数
- [ ] 构建缓存（buildx gha cache）与镜像构建提速
