# test 环境

> VPC：css-non-prod（10.20.0.0/16）· 分支：`test` · 全自动部署（push 即上）
> 总拓扑与账号约束见 [README.md](README.md)；CI/CD 细节见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md)。

## 定位

日常开发验证环境。老仓库（ChainServiceSolutions）的代码定时合并进新仓库 `test` 分支后，第一站在这里验证；也是 CI/CD 流水线的首个打通目标。数据可弃（迁移不打快照）。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 `css-test-app` = **`i-0cb9b69b9eb19a9aa`**（2026-07-30 由 Terraform 重建，ID 已变；key pair `css-test`，根卷已加密），m7i-flex.large（2C/8G），私网 **10.20.10.10**，**私有子网，无公网 IP** |
| 入口 | **ALB `css-test`** → `http://css-test-524317374.us-east-1.elb.amazonaws.com/`（目标 10.20.10.10:80，healthy，实测 200）；每环境一个独立 ALB，不再共享、不再按 Host 分流 |
| S3 桶 | **`css-test-582797602427`**（后端 `S3_STORAGE_BUCKET_NAME`）——纯名 `css-test` 被别的 AWS 账号占用，回退带账号后缀；旧桶 `css-test-storage-582797602427` 已退役删除。访问身份 IAM 用户 `css-app-test`（内联策略只授权本桶，key 用时 `07-获取应用iam密钥/issue-app-s3-key.sh test --new-key`）。⚠️ **临时债**：桶已开对象公有读（改 presigned 后回收） |
| 监控 | ✅ CloudWatch：9 条告警 + Dashboard `css-test` + SNS 主题 `css-test-alarms`（已订阅 charles@shinypathway.com + 2219002126@qq.com，确认状态待核实）。由 css-terraform `test/monitoring` stack 管理，见其 `使用说明/10-监控与账单.md` |
| 运行内容 | 三栈 compose：`css-test-{infra,backend,frontend}`（redis/rabbitmq/kafka + app 系 11 容器 + frontend） |
| 数据库 | RDS `css-non-prod`（PG16.14，仅内网）的 **`css-test-main`** + **`css-test-ocr`** 库。应用连库账号 **`css_app_test`**（2026-07-30 起，低权专用账号；密码写死不轮换，改密走 `05-数据库运维/change-db-password.sh`）；master `postgres` 仅运维用（Secrets Manager 托管，**7 天自动轮换**）。endpoint 与凭证见工作区 `运维访问速查.local.md` |
| 数据脱敏 | ✅ **2026-07-29 已脱敏**（`05-数据库运维/anonymize-db.sh test`）：所有 email 值前加 `1`、phone 值后加 `1`、所有 `password_hash` 统一为口令 **`Test1234!`**。**登录用原邮箱前面加 `1`（如 `1foo@bar.com`）+ 口令 `Test1234!`**。共 188 个账号，实测残留 0 条。<br/>口令哈希 = pbkdf2_hmac sha256 + env 的 `PASSWORD_SALT` + 10 万次迭代——**换 salt 必须重跑脚本**，否则登录全失败 |
| 镜像 | ECR `<registry>/test/css-backend/*` 与 `test/css-frontend/app`，tag `test-vN`（不可变版本号，N=Actions run 序号，如 `test-v12`）+ `test`（浮动）；手动推送 `test-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/test/backend.env`、`/css/test/frontend.env` |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/test/*` 参数；EC2 标签 **`Environment=css-test`**（部署与 IAM 条件按它定位，旧 `CssEnv` 已废除） |

## 访问方式

> 凭证与完整命令见工作区 `运维访问速查.local.md`（gitignore）。

| 目的 | 方式 |
|------|------|
| 打开 test 页面 | **`http://css-test-524317374.us-east-1.elb.amazonaws.com/`**（ALB `css-test`，公网可达）。域名在 GoDaddy（不用 Route53），HTTPS 未开 |
| SSH 上服务器 | `ssh -i ~/.ssh/css-test.pem -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' ec2-user@10.20.10.10`（堡垒机 `css-non-prod-bastion` 是唯一入口，本机密钥文件名沿用 `css-non-prod-gw.pem`；开发者临时钥走 `06-服务器密钥与访问/grant-dev-ssh.sh`） |
| 连数据库 | 经堡垒机隧道：`ssh -i ~/.ssh/css-non-prod-gw.pem -N -L 5433:<rds端点>:5432 ec2-user@3.225.148.166` 后本地 psql `localhost:5433`（应用账号 `css_app_test`，见速查文件） |
| 看 2FA 验证码 | kafka-ui：**开发入口 ALB** `http://css-non-prod-entry-1482605872.us-east-1.elb.amazonaws.com:8085`（白名单 `221.214.0.190/32` + `134.195.101.194/32`；业务 ALB 的 8085 已撤除） |

## 部署方式（CI/CD）

✅ **全自动（2026-07-31 现状）**：`git push neworg test` → GitHub Actions（lint → 单测 → build → push ECR `test-vN`+`test`）→ **migrate → SSM 部署**（按 tag `Environment=css-test` 定位实例）→ 服务器 `deploy.sh test deploy`（Parameter Store 渲染 env → pull → up --wait → 冒烟 → prune）。migrate 无快照（数据可弃）。约 10~15 分钟。兜底：手动 `docs/新aws账号/09-远程执行与手动部署/deploy-env.sh test`。

## 现状（2026-07-31）

- **基础设施已全部由 css-terraform 纳管**（资源 ID/用法以其 `CLAUDE.md`、`使用说明/` 为准）；应用机 2026-07-30 重建为 `i-0cb9b69b9eb19a9aa`（私网 IP 不变，根卷加密），三栈运行中。
- **数据库**：`css-test-main`/`css-test-ocr` 载入 preprod 数据并脱敏；应用已切低权账号 `css_app_test`（07-30）。
- **入口**：`css-test` ALB 正常（前端 200）；kafka-ui 走开发入口 ALB `:8085`。
- **监控**：9 告警 + Dashboard；SNS 已订阅两邮箱（确认状态待核实）。
- **待做**：① 绑域名 → ACM（GoDaddy 手动 CNAME 验证）→ 443 监听器 → 前端 `VITE_API_BASE_URL`/`VITE_WS_BASE_URL` 改成域名并**重建前端镜像**（构建期烤入，重启无效）；② S3 对象公有读回收（改 presigned）。
- **RDS 升配待办**（test/uat 共用的 `css-non-prod`）：升 db.t4g.small 被 **Free plan 拦截**，升 Paid 后改 css-terraform `database` stack 变量；瓶颈是内存不是 CPU。
- 登录：邮箱是原邮箱**前面加 `1`**，口令统一 `Test1234!`；2FA 验证码去 kafka-ui 的 `sms_send` topic 看。
