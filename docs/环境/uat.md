# uat 环境

> VPC：css-non-prod（10.20.0.0/16）· 分支：`uat` · 自动部署（迁移前自动打 RDS 快照）
> 总拓扑与账号约束见 [README.md](README.md)。

## 定位

预发布验收环境。test 验证通过的代码 `merge test → push uat` 晋级到这里做验收；数据比 test 更接近真实，迁移前自动快照兜底。

## 目标形态

| 项 | 值 |
|----|----|
| 服务器 | EC2 `css-uat-app` = **`i-0f90c5c061d640a27`**（2026-07-30 由 Terraform 重建，ID 已变；key pair `css-uat`，根卷已加密），m7i-flex.large（2C/8G），私网 **10.20.11.10**，**私有子网，无公网 IP**，与 test 各自独立一台（2vCPU 机器跑一套全栈已见过 CPU 崩溃循环，不同机） |
| 入口 | **ALB `css-uat`** → `http://css-uat-1366981991.us-east-1.elb.amazonaws.com/`（目标 10.20.11.10:80；uat 未部署，目标**暂 unhealthy 属正常**，ALB 此时返回 503）。每环境一个独立 ALB，不再共享、不再按 Host 分流 |
| S3 桶 | **`css-uat-582797602427`**（后端 `S3_STORAGE_BUCKET_NAME`；与 test/prod 统一带账号后缀）。⚠️ **临时债**：桶已开对象公有读（改 presigned 后回收） |
| 运行内容 | 三栈 compose：`css-uat-{infra,backend,frontend}` |
| 数据库 | RDS `css-non-prod`（PG16.14）的 **`css-uat-main`** + **`css-uat-ocr`** 库 ✅ **已建**（=test 数据：146 表 / 188 用户，已脱敏）。应用连库账号 **`css_app_uat`**（低权专用，密码写死不轮换）。⚠️ 实例升配 `db.t4g.small` 被 Free plan 拦截（内存是瓶颈），升 Paid 后改 css-terraform `database` stack 变量 |
| 监控 | CloudWatch 9 条告警 + Dashboard `css-uat` + SNS `css-uat-alarms`（已订阅两邮箱，确认状态待核实）。uat 未部署期间 `alb-no-healthy-target` 处于 ALARM 属正常。由 css-terraform `uat/monitoring` stack 管理 |
| 镜像 | ECR `uat/css-*` 仓库，tag `uat-vN`（不可变版本号）+ `uat`（浮动）；手动推送 `uat-manual-<sha7>` |
| 环境变量 | SSM Parameter Store `/css/uat/backend.env`、`/css/uat/frontend.env`（`API_KEY==VITE_X_API_KEY` 由 CI 校验） |
| 实例角色 | SSM 托管核心 + ECR 只读 + 读 `/css/uat/*`；EC2 标签 **`Environment=css-uat`**（旧 `CssEnv` 已废除） |

## 访问方式

> 凭证与完整命令见工作区 `运维访问速查.local.md`（gitignore）。

| 目的 | 方式 |
|------|------|
| 打开 uat 页面 | **`http://css-uat-1366981991.us-east-1.elb.amazonaws.com/`**（ALB `css-uat`；部署前返回 503） |
| SSH 上服务器 | `ssh -i ~/.ssh/css-uat.pem -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' ec2-user@10.20.11.10`（堡垒机 `css-non-prod-bastion`，密钥文件名沿用 `css-non-prod-gw.pem`；一机一钥，个人钥 `~/.ssh/wenchao` 作备用） |
| 数据库 | 与 test 相同：经堡垒机隧道（应用账号 `css_app_uat`） |
| kafka-ui | **开发入口 ALB** `http://css-non-prod-entry-1482605872.us-east-1.elb.amazonaws.com:8086`（白名单访问） |

## 部署方式（CI/CD）

✅ **全自动（2026-07-31 现状）**：test 验证 OK → `git checkout uat && git merge test && git push neworg uat` → 与 test 同一条流水线（build → migrate → SSM 部署），仅两处不同：目标机标签 `Environment=css-uat`、**migrate 前自动创建 RDS 快照**。兜底：手动 `docs/新aws账号/09-ssm-run-command/deploy-env.sh uat`。

## 现状（2026-07-31）

**已就绪**：基础设施全部由 css-terraform 纳管——应用机 `css-uat-app` ✅（07-30 重建，**未部署**）、
ALB `css-uat` ✅（目标已注册，等部署后转 healthy）、S3 桶 ✅、监控 ✅、
库 `css-uat-main`/`css-uat-ocr` ✅ **已建且已载入 test 数据（已脱敏，登录=原邮箱前加 `1` + 口令 `Test1234!`）**、库账号 `css_app_uat` ✅。

**待做**：① 以工作区根 `deploy-env/uat/backend.env.example` 为底稿填值（注意 `POSTGRES_DB=css-uat-main`、
`S3_STORAGE_BUCKET_NAME=css-uat-582797602427`、`OCR_*_URL` 指向 `css-uat-ocr`、库账号用 `css_app_uat`）→
`11-parameter-store/put-params.sh uat` → ② push `uat` 分支走 CI 自动构建+部署 → ③ 经 ALB 验证。
