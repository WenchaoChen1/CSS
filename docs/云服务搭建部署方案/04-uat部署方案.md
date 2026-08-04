# 04 · uat 环境部署方案（2026-08-04 制定，基于当日实查）

> ✅ **已于当日执行完成**：拍板 D1=test 全量合入、D2=uat-demo.chain-serve.com。
> 参数灌入（backend v2/frontend v3，唯一修正=WS 地址从 ALB DNS 改域名口径）→ merge test→uat 推送
> → CI 构建 `uat-v17`(后端)/`uat-v19`(前端) + migrate + deploy core 全自动成功；
> **前端栈 CI 未部署**（两 workflow 版本号各自编，属预期分工），手动
> `deploy-env.sh uat frontend uat-v19` 补齐。验收：ALB 目标 healthy、前端 200、
> `/api` 无 key 401、`css-uat-alb-no-healthy-target` 自动转 OK。
> 遗留：GoDaddy 的 uat-demo CNAME 待配（WS 功能依赖）；OPENAI/GEMINI/MAPS 三个 key
> 缺口见 `docs/新老环境配置对比报告-2026-08-04.md`。

> 目标：把 uat 从"只建机未部署"拉到"三栈可用、ALB 200、可登录验收"。
> 本方案只列计划不执行；执行前逐项过一遍 §1 的前提核查结论。

---

## 1. 现状实查（2026-08-04，全部只读验证过）

### 已就绪 ✅（这些不用做）

| 项 | 实况 |
|---|---|
| EC2 `css-uat-app` | i-0f90c5c061d640a27（10.20.11.10，m7i-flex.large），**SSM Online**，user_data 已装 docker/compose |
| ALB `css-uat` | css-uat-1366981991.us-east-1.elb.amazonaws.com，目标 unhealthy（机上无服务，预期） |
| RDS | 共享 `css-non-prod` **已升 db.t4g.small（2GB）**——uat 上线的内存前置已满足；库 `css-uat-main`/`css-uat-ocr` 已建（数据=test 副本、已脱敏）；低权账号 `css_app_uat` 已建、owner 已 reown |
| ECR | `uat/*` 7 个仓库已建（**但零镜像**，见缺口） |
| SG/IAM/SSM 参数壳/S3 桶 | 全部由 css-terraform 纳管，plan 零漂移 |
| 监控 | uat 5 条告警（ALB×3+EC2×2）+ Dashboard + SNS 双邮箱已确认；日志组 `/css/uat`（14 天） |
| kafka-ui 入口 | entry ALB `:8086`（白名单），认证凭证=uat env 的 SPRING_SECURITY_* |

### 三个硬缺口 ❌（部署前必须补）

| # | 缺口 | 实查证据 |
|---|---|---|
| G1 | **SSM 参数是占位符**：`/css/uat/backend.env`、`/css/uat/frontend.env` 的 v1 值是 TF 参数壳的 PLACEHOLDER 占位句，**不是真实配置**（解析出 0 个键）。此前文档"uat 参数已有真实值"的说法有误 | boto3 读值解析 0 键 |
| G2 | **ECR uat 零镜像**：CI 从未构建过 uat（describe-images 空） | `uat/css-backend/app`、`uat/css-frontend/app` 均 `[]` |
| G3 | **uat 分支没有 CI**：前后端仓库的 `.github/workflows/cicd.yml` 与 `deploy/` 资产只在 test 分支（提交 `8d757c13`/前端同批），uat 分支=main 老代码——**push uat 什么都不会触发** | `git ls-tree uat .github/workflows/` 为空 |

---

## 2. 两个决策点（执行前拍板）

### D1：uat 用哪条代码线？

| 选项 | 内容 | 推荐 |
|---|---|---|
| **A. test 全量合入 uat**（merge test → uat） | uat 拿到 CI/CD 资产 + sentry 三个提交，与 test 完全同源 | ⭐ 推荐：uat 本来就该验证 test 通过的东西；且 G3 反正要合 CI 资产，拆着合反而多一条差异线 |
| B. 只 cherry-pick CI 资产提交 | uat 保持 main 代码 + 仅补 cicd.yml/deploy/ | 不推荐：sentry 代码尚未在任何环境验证的说法不成立（test 已在跑），且 cherry-pick 制造永久分叉 |

### D2：uat 对外地址用什么口径？

| 选项 | 影响 |
|---|---|
| **A. 先用 ALB DNS**（css-uat-1366981991...elb.amazonaws.com） | 立即可用；`PATH_BASE`/`VITE_API_BASE_URL` 填 ALB DNS；将来换域名要**重建前端镜像**（VITE_* 构建期烤入） |
| B. 直接上 `uat-demo.chain-serve.com` | 需先在 GoDaddy 手动加 CNAME → css-uat ALB 并验证解析；一步到位不用二次重建前端 |

> 若 08-03 配域名那批工作已把 uat-demo 的 CNAME 加好（执行时用 `nslookup uat-demo.chain-serve.com` 验证），选 B；否则选 A 或先去 GoDaddy 加记录。

---

## 3. 执行步骤（依赖顺序固定，约半天）

### 阶段一：参数面（G1，~1h，最费心的一步）

1. 以 `deploy-env/test/backend.env.remote-bak`（92 键，=线上 test 现值）为底本，制作 `deploy-env/uat/backend.env`，逐键改 uat 差异：
   - `POSTGRES_DB=css-uat-main`、OCR 两个 URL 指向 `css-uat-ocr`、`POSTGRES_USER=css_app_uat` + 对应密码（在 `运维访问速查.local.md`）
   - `S3_STORAGE_BUCKET_NAME=css-uat-582797602427` + `css-app-uat` 的 AK/SK（无 key 则 `07-获取应用iam密钥/issue-app-s3-key.sh uat --new-key`）
   - `API_KEY`/`JWT_SECRET` **重新生成**（各环境独立，勿抄 test）
   - ⚠️ **`PASSWORD_SALT` 必须抄 test 的值**——uat 库数据是 test 副本，哈希绑 salt，换 salt = 188 个脱敏账号（口令 `Test1234!`）全部登不进（历史踩过：css-test-runtime 的 salt 事故）
   - `PATH_BASE` 按 D2 结果；`TWILIO_*` 保持占位+禁用（sms_sender 缺变量会崩溃循环）；`SPRING_SECURITY_USER_PASSWORD` 新生成（kafka-ui :8086 的登录密码）
   - Sentry/邮件/Eden 键对照 test 现值按 uat 口径填（08-03 新增的那批）
2. 制作 `deploy-env/uat/frontend.env`（7 键）：`VITE_API_BASE_URL`/`VITE_WS_BASE_URL` 按 D2；**`VITE_X_API_KEY` == 上面新生成的 `API_KEY`**（不等则全 401）；`VITE_SENTRY_*` 按 uat 口径
3. 灌参数：`docs/环境运维执行脚本/11-parameter-store/put-params.sh uat`（脚本自带远程键级比对+确认）
4. 核对：用 boto3 读回做耦合校验（API_KEY==VITE_X_API_KEY、CATALOG_OCR_API_KEY==OCR_API_KEY、salt==test）

### 阶段二：代码面（G2+G3，合并触发 CI）

5. 前后端各执行：`git checkout uat && git merge test`（fast-forward 或干净 merge）`&& git push neworg uat`
6. push 自动触发 GitHub Actions：构建 6+1 镜像推 ECR（`uat-v1` + 浮动 `uat`）→ SSM 上传 bundle 到 uat 机 `/opt/css-cicd/` → `deploy.sh uat migrate all` → `deploy core` → 前端 workflow 构建（烤入 `/css/uat/frontend.env` 的 VITE_*）→ `deploy frontend`
7. 盯 Actions 日志；CI 部署环节失败的兜底：`docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh uat`

### 阶段三：验收（~0.5h）

8. ALB 目标转 healthy、`http://<uat入口>/` 前端 200、`/api` 无 key 401（门禁生效）
9. 登录链路：脱敏账号 + `Test1234!` → 2FA 验证码去 kafka-ui（entry `:8086`，SPRING_SECURITY 凭证）读 `sms_send` topic → 登录成功。**登录 500 先查 kafka 容器**（auth 硬依赖）、再查 salt
10. 监控收尾：`css-uat-alb-no-healthy-target` 从 ALARM 转 OK；Dashboard 曲线出数；CloudWatch Logs `/css/uat` 各 stream 产生
11. 共享 RDS 观察：两环境同跑后看 `css-test-rds-memory-low`（现 2GB 应扛得住；这条告警名义在 test 但反映共用实例）

### 回滚

- uat 无真实用户，回滚压力小：`deploy.sh uat` 支持按 `.last_good_uat` 回退镜像 tag；首次部署无 last_good，回滚=stop 三栈
- 数据层：uat 库坏了直接从 test 库重同步（`05-数据库运维` 的库到库同步）+ 重跑 reown

---

## 4. 风险与坑（执行时对照）

| 坑 | 处置 |
|---|---|
| PASSWORD_SALT 不一致 → 登录全挂 | 阶段一第 1 步显式抄 test 值；阶段三第 9 步登录验证兜底 |
| API_KEY ≠ VITE_X_API_KEY → 全 401 | 阶段一第 4 步耦合校验 |
| sms_sender/email_sender 缺变量崩溃循环 | TWILIO/SMTP 保持 test 同款占位+禁用策略 |
| VITE_* 烤入镜像 → 换地址要重建前端 | D2 尽量一步定对；换域名时只重建前端 workflow 即可 |
| CI 首跑 uat 可能踩 GitHub Environment 保护/OIDC sub | trust policy 已含 uat 分支+environment 形态（08-03 审计核对过），失败看 Actions 的 AssumeRole 报错 |
| kafka 不可达 → 登录 500 | infra 栈先起（deploy.sh 顺序已保证）；这也是 ocean-island 已立项要修的硬依赖 |

## 5. 明确不在本方案内

- prod 开闸（`enable_prod_compute`）、HTTPS/ACM、RDS Multi-AZ——等 prod 节奏
- S3 公读债回收（presigned 改造 2-5 人日，专项）
- uat 独立数据集（当前=test 副本，够验收用）
