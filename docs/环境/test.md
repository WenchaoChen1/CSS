# test 环境

> VPC：css-non-prod（10.20.0.0/16）· 分支：`test` · 全自动部署（push 即上）
> 总拓扑与账号约束见 [README.md](README.md)；CI/CD 细节见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md)。

## 定位

日常开发验证环境。老仓库（ChainServiceSolutions）的代码定时合并进新仓库 `test` 分支后，第一站在这里验证；也是 CI/CD 流水线的首个打通目标。数据可弃（迁移不打快照）。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 t3.large（2c8G，对齐现机 m7i-flex.large 的 8G 内存），**私有子网，无公网 IP** |
| 运行内容 | 三栈 compose：`css-test-{infra,backend,frontend}`（redis/rabbitmq/kafka + app 系 11 容器 + frontend） |
| 数据库 | RDS `css-non-prod`（新 VPC，PG16.14，endpoint `css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com`，master 用户 postgres）的 **`css-test-main`** + **`css-test-ocr`** 库（✅ 已用 `docs/新aws账号/05-数据同步/restore-dump-via-gw.sh` 载入 preprod 数据；私有子网、仅内网访问） |
| 镜像 | ECR `<registry>/test/css-backend/*` 与 `test/css-frontend/app`，tag `test-vN`（不可变版本号，N=Actions run 序号，如 `test-v12`）+ `test`（浮动）；手动推送 `test-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/test/backend.env`、`/css/test/frontend.env` |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/test/*` 参数；EC2 标签 `CssEnv=css-test` |

## 访问方式

| 目的 | 方式 |
|------|------|
| 打开 test 页面 | `http://3.225.148.166/`（网关机 nginx 反代到 test:80；仅 `221.214.0.190/32` 可达。**过渡通道**：ALB + 域名就绪后收掉，Web 访问统一走 ALB 域名） |
| SSH 上服务器 | `ssh -J <网关机> <test私网IP>`（ProxyJump，堡垒是唯一入口） |
| 连数据库 | 经网关机隧道：`ssh -L 5432:<rds端点>:5432 <网关机>` 后本地 psql |
| 看 2FA 验证码 | kafka-ui（infra 栈 tools profile），经 SSH 隧道访问 8085 |

## 部署方式（CI/CD）

> ⚠️ **现状（2026-07-28）**：CI 只推镜像（workflow 中 migrate/deploy job 已注释）；部署 = 手动执行 `docs/新aws账号/09-ssm-run-command/deploy-env.sh test`。下述全自动链路为恢复注释后的目标态。

`git push neworg test` → GitHub Actions（lint → 单测 → build → push ECR）→ SSM Run Command → 服务器 `deploy.sh test deploy`（Parameter Store 渲染 env → pull → up --wait → 冒烟 → prune）→ 自动 `migrate`（无快照，数据可弃）。约 10~15 分钟。

## 现状与迁移路径（2026-07-28）

- **旧资源已清**：旧默认 VPC 的 test EC2 `i-08e110b5a5425980d`（100.30.61.207）已删除、EIP 已释放；旧默认 VPC 的 RDS 同名实例也已删除。当前账号无任何应用机。
- **数据库已就位**：新 VPC RDS `css-non-prod` 的 `css-test-main`/`css-test-ocr` 已从 preprod 备份载入（`restore-dump-via-gw.sh`：本地 dump → S3 中转桶 → SSM 经网关机 pg_restore）。
- **待做**：用 `docs/新aws账号/06-ec2/create-app-ec2.sh` 在新 VPC 私有子网创建 test 应用机 → CI 推镜像后手动 `deploy-env.sh test` 部署 → 前端 `VITE_WS_BASE_URL` 改烤网关 EIP（ALB 就绪后改域名）→ 端到端验证。
- 登录测试账号、salt 等运行时注意事项沿用现状（见项目 CLAUDE.md 与记忆）。
