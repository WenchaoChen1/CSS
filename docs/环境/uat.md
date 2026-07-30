# uat 环境

> VPC：css-non-prod（10.20.0.0/16）· 分支：`uat` · 自动部署（迁移前自动打 RDS 快照）
> 总拓扑与账号约束见 [README.md](README.md)。

## 定位

预发布验收环境。test 验证通过的代码 `merge test → push uat` 晋级到这里做验收；数据比 test 更接近真实，迁移前自动快照兜底。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 `css-uat-app` = `i-00c635f52140cf035`，m7i-flex.large（2C/8G），私网 **10.20.11.10**，**私有子网，无公网 IP**，与 test 各自独立一台（2vCPU 机器跑一套全栈已见过 CPU 崩溃循环，不同机） |
| 入口 | **ALB `css-uat`** → `http://css-uat-1366981991.us-east-1.elb.amazonaws.com/`（目标 10.20.11.10:80；uat 未部署，目标**暂 unhealthy 属正常**，ALB 此时返回 503）。每环境一个独立 ALB，不再共享、不再按 Host 分流 |
| S3 桶 | **`css-uat-582797602427`**（后端 `S3_STORAGE_BUCKET_NAME`，纯名拿到了，无需账号后缀） |
| 运行内容 | 三栈 compose：`css-uat-{infra,backend,frontend}` |
| 数据库 | RDS `css-non-prod`（新 VPC，PG16.14，✅ 实例已建成）的 **`css-uat-main`** + **`css-uat-ocr`** 库（待建，`docs/新aws账号/05-数据同步/create-databases.sh` 创建，ocr 库自动加 pgvector）。⚠️ 实例升配 `db.t4g.small` 被 Free plan 拦截（内存是瓶颈），升 Paid 后跑 `04-rds/resize-rds.sh` |
| 监控（2026-07-29 ✅） | CloudWatch 9 条告警 + Dashboard `css-uat` + SNS `css-uat-alarms`（⚠️ 尚无订阅者）。uat 未部署期间 `alb-no-healthy-target` 处于 ALARM 属正常。手册：`docs/新aws账号/14-cloudwatch/README.md` |
| 镜像 | ECR `uat/css-*` 仓库，tag `uat-vN`（不可变版本号）+ `uat`（浮动）；手动推送 `uat-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/uat/backend.env`、`/css/uat/frontend.env`（`API_KEY==VITE_X_API_KEY` 由 CI 校验） |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/uat/*`；EC2 标签 `CssEnv=css-uat` |

## 访问方式

| 目的 | 方式 |
|------|------|
| 打开 uat 页面 | **`http://css-uat-1366981991.us-east-1.elb.amazonaws.com/`**（ALB `css-uat`；部署前返回 503）。<br/>~~`http://3.225.148.166:8080/`~~ 网关机反代 **2026-07-29 已收掉**（nginx 停用禁用、SG 的 80/8080 已撤销） |
| SSH 上服务器 | `ssh -i ~/.ssh/css-uat.pem -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' ec2-user@10.20.11.10`（一机一钥；个人钥 `~/.ssh/wenchao` 作备用） |
| 数据库 | 与 test 相同：经网关机隧道 |

## 部署方式（CI/CD）

test 验证 OK → `git checkout uat && git merge test && git push neworg uat` → 与 test 同一条流水线，仅两处不同：目标机标签 `CssEnv=css-uat`、**migrate 前自动创建 RDS 快照**。
（⚠️ 现状：CI 只推镜像，自动部署 job 已注释；部署 = 手动 `docs/新aws账号/09-ssm-run-command/deploy-env.sh uat`。）

## 现状（2026-07-29）

**已就绪**：css-non-prod VPC ✅、RDS 实例 `css-non-prod` ✅、应用机 `css-uat-app` ✅（已建机，**未部署**）、
ALB `css-uat` ✅（目标已注册，等部署后转 healthy）、S3 桶 `css-uat` ✅、专属 key pair `css-uat` ✅。

**待做**：① 建库 `css-uat-main`/`css-uat-ocr`（`05-数据同步/create-databases.sh`）→ ② 载入数据后**必须**跑
`05-数据同步/anonymize-db.sh uat` 脱敏（email 前缀 `1` / phone 后缀 `1` / 口令统一 `Test1234!`）→
③ 以工作区根 `deploy-env/uat/backend.env.example` 为底稿填值（注意 `POSTGRES_DB=css-uat-main`、
`S3_STORAGE_BUCKET_NAME=css-uat`、`OCR_*_URL` 指向 `css-uat-ocr`）→ `11-parameter-store/put-params.sh uat` →
④ CI 推 uat 镜像 → `09-ssm-run-command/deploy-env.sh uat` 部署 → ⑤ 经 ALB 验证。
