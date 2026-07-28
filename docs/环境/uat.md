# uat 环境

> VPC：css-non-prod（10.20.0.0/16）· 分支：`uat` · 自动部署（迁移前自动打 RDS 快照）
> 总拓扑与账号约束见 [README.md](README.md)。

## 定位

预发布验收环境。test 验证通过的代码 `merge test → push uat` 晋级到这里做验收；数据比 test 更接近真实，迁移前自动快照兜底。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 t3.large（2c8G），**私有子网，无公网 IP**，与 test 各自独立一台（现 2vCPU 机器跑一套全栈已见过 CPU 崩溃循环，不同机） |
| 运行内容 | 三栈 compose：`css-uat-{infra,backend,frontend}` |
| 数据库 | RDS `css-non-prod`（新 VPC，PG16.14，✅ 实例已建成）的 **`css-uat-main`** + **`css-uat-ocr`** 库（待建，`docs/新aws账号/05-数据同步/create-databases.sh` 创建，ocr 库自动加 pgvector） |
| 镜像 | ECR `uat/css-*` 仓库，tag `uat-vN`（不可变版本号）+ `uat`（浮动）；手动推送 `uat-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/uat/backend.env`、`/css/uat/frontend.env`（`API_KEY==VITE_X_API_KEY` 由 CI 校验） |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/uat/*`；EC2 标签 `CssEnv=css-uat` |

## 访问方式

| 目的 | 方式 |
|------|------|
| 打开 uat 页面 | `http://<非生产网关机EIP>:8080/`（网关 nginx :8080 反代到 uat:80；仅 `221.214.0.190/32`） |
| SSH / 数据库 | 与 test 相同：经网关机 ProxyJump / 隧道 |

## 部署方式（CI/CD）

test 验证 OK → `git checkout uat && git merge test && git push neworg uat` → 与 test 同一条流水线，仅两处不同：目标机标签 `CssEnv=css-uat`、**migrate 前自动创建 RDS 快照**。
（⚠️ 现状：CI 只推镜像，自动部署 job 已注释；部署 = 手动 `docs/新aws账号/09-ssm-run-command/deploy-env.sh uat`。）

## 现状（2026-07-28）

待建：uat 应用机（`docs/新aws账号/06-ec2/create-app-ec2.sh`）、`css-uat-main`/`css-uat-ocr` 库、Parameter Store 参数。已就绪：css-non-prod VPC（✅）+ RDS 实例 `css-non-prod`（✅ 2026-07-28 新 VPC 建成）。uat 的环境变量以工作区根 `deploy-env/uat/backend.env.example` 为底稿填值后入 Parameter Store。
