# test 环境

> VPC：css-non-prod（10.20.0.0/16）· 分支：`test` · 全自动部署（push 即上）
> 总拓扑与账号约束见 [README.md](README.md)；CI/CD 细节见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md)。

## 定位

日常开发验证环境。老仓库（ChainServiceSolutions）的代码定时合并进新仓库 `test` 分支后，第一站在这里验证；也是 CI/CD 流水线的首个打通目标。数据可弃（迁移不打快照）。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 `css-test-app` = `i-0b3e73ed51811b69c`，m7i-flex.large（2C/8G），私网 **10.20.10.10**，**私有子网，无公网 IP** |
| 入口 | **ALB `css-test`** → `http://css-test-524317374.us-east-1.elb.amazonaws.com/`（目标 10.20.10.10:80，healthy，实测 200）；每环境一个独立 ALB，不再共享、不再按 Host 分流 |
| S3 桶 | **`css-test-582797602427`**（后端 `S3_STORAGE_BUCKET_NAME`）——纯名 `css-test` 被别的 AWS 账号占用，回退带账号后缀；旧桶 `css-test-storage-582797602427` 的 102 个对象已迁入、参数已更新，**旧桶已退役删除**（`13-s3/retire-bucket.sh`）。访问身份 IAM 用户 `css-app-test`（内联策略只授权本桶，⏳ key 暂未生成，用时 `07-iam/create-app-s3-user.sh test --new-key`） |
| 监控 | ✅ CloudWatch：9 条告警 + Dashboard `css-test` + SNS 主题 `css-test-alarms`（⚠️ **无订阅者**，告警响了没人收）。见 [../新aws账号/14-cloudwatch/README.md](../新aws账号/14-cloudwatch/README.md) |
| 运行内容 | 三栈 compose：`css-test-{infra,backend,frontend}`（redis/rabbitmq/kafka + app 系 11 容器 + frontend） |
| 数据库 | RDS `css-non-prod`（新 VPC，PG16.14，endpoint `css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com`，master 用户 postgres）的 **`css-test-main`** + **`css-test-ocr`** 库（✅ 已用 `docs/新aws账号/05-数据同步/restore-dump-via-gw.sh` 载入 preprod 数据；私有子网、仅内网访问） |
| 数据脱敏 | ✅ **2026-07-29 已脱敏**（`05-数据同步/anonymize-db.sh test`）：所有 email 值前加 `1`、phone 值后加 `1`、所有 `password_hash` 统一为口令 **`Test1234!`**。**登录用原邮箱前面加 `1`（如 `1foo@bar.com`）+ 口令 `Test1234!`**。共 188 个账号，实测残留 0 条。<br/>口令哈希 = pbkdf2_hmac sha256 + env 的 `PASSWORD_SALT` + 10 万次迭代——**换 salt 必须重跑脚本**，否则登录全失败 |
| 镜像 | ECR `<registry>/test/css-backend/*` 与 `test/css-frontend/app`，tag `test-vN`（不可变版本号，N=Actions run 序号，如 `test-v12`）+ `test`（浮动）；手动推送 `test-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/test/backend.env`、`/css/test/frontend.env` |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/test/*` 参数；EC2 标签 `CssEnv=css-test` |

## 访问方式

| 目的 | 方式 |
|------|------|
| 打开 test 页面 | **`http://css-test-524317374.us-east-1.elb.amazonaws.com/`**（ALB `css-test`，公网可达）。绑域名 + ACM 证书后走 443 域名。<br/>~~`http://3.225.148.166/`~~ 网关机反代 **2026-07-29 已收掉**（nginx 停用禁用、SG 的 80/8080 已撤销） |
| SSH 上服务器 | `ssh -i ~/.ssh/css-test.pem -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' ec2-user@10.20.10.10`（堡垒是唯一入口；一机一钥，个人钥 `~/.ssh/wenchao` 作备用） |
| 连数据库 | 经网关机隧道：`ssh -i ~/.ssh/css-non-prod-gw.pem -N -L 5433:<rds端点>:5432 ec2-user@3.225.148.166` 后本地 psql `localhost:5433` |
| 看 2FA 验证码 | kafka-ui（infra 栈 tools profile），经 SSH 隧道访问 8085（**故意不挂 ALB**） |

## 部署方式（CI/CD）

> ⚠️ **现状（2026-07-28）**：CI 只推镜像（workflow 中 migrate/deploy job 已注释）；部署 = 手动执行 `docs/新aws账号/09-ssm-run-command/deploy-env.sh test`。下述全自动链路为恢复注释后的目标态。

`git push neworg test` → GitHub Actions（lint → 单测 → build → push ECR）→ SSM Run Command → 服务器 `deploy.sh test deploy`（Parameter Store 渲染 env → pull → up --wait → 冒烟 → prune）→ 自动 `migrate`（无快照，数据可弃）。约 10~15 分钟。

## 现状（2026-07-29）

- **旧资源已清**：旧默认 VPC 的 test EC2 `i-08e110b5a5425980d`（100.30.61.207）与同名 RDS 实例已于 2026-07-28 删除、EIP 已释放。
- **应用机已建并部署**：`css-test-app` `i-0b3e73ed51811b69c`（10.20.10.10），三栈 `css-test-{infra,backend,frontend}` 运行中。
- **数据库已就位并脱敏**：`css-test-main`/`css-test-ocr` 从 preprod 备份载入（`restore-dump-via-gw.sh`），2026-07-29 执行 `anonymize-db.sh test`。
- **入口已切 ALB**：`css-test` ALB 建成，目标 healthy，前端实测 200；网关机 80/8080 过渡通道已收（`12-alb/revoke-gw-proxy.sh`）。
- **S3 已切新桶**：`css-test-582797602427`，旧桶 102 个对象已迁入，旧桶已退役删除。
- **监控已配**：CloudWatch 9 条告警 + Dashboard（`14-cloudwatch/create-monitoring.sh test`）。
- **待做**：① 给 SNS 主题 `css-test-alarms` **加订阅邮箱并点确认链接**（现在告警没人收）；
  ② 绑域名 → ACM 证书 → 443 监听器 → 前端 `VITE_API_BASE_URL`/`VITE_WS_BASE_URL` 改成域名并**重建前端镜像**（构建期烤入，重启无效）；
  ③ 恢复 workflow 里注释掉的 migrate/deploy job 实现全自动部署。
- **RDS 升配待办**（test/uat 共用的 `css-non-prod`）：⚠️ 升 db.t4g.small 被 **Free plan 拦截**，等升级 Paid plan；瓶颈是内存（可用仅 146MB），不是 CPU。
- 登录：邮箱是原邮箱**前面加 `1`**，口令统一 `Test1234!`；2FA 验证码去 kafka-ui 的 `sms_send` topic 看。
