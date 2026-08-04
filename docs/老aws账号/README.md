# 迁移工具手册 · 老 AWS 账号数据拉取（dev 旧组织 → larry 新组织）

本文件夹 = **老 AWS 账号（`021213872872` / eu-central-1，全容器无 RDS）三个环境的访问开通与数据拉取工具**。
把配置、数据库、S3 拉到本机 `备份/`，为迁移到 larry 新组织（`582797602427` / us-east-1）做准备。

三个环境：`dev`(3.124.149.172)、`stage`(52.28.87.199)、`preprod`(3.74.51.100)，登录用户均为 `ubuntu`。
**2026-08-03 起三台机器 SSH 全部开通**（此前只有 preprod 有）。

> ⚠️ 老账号是**只读数据迁移源**：除"给自己装 SSH 公钥"外，禁止在其上做任何变更
> （启停实例、改安全组、删桶对象、改数据一律禁止）；所有写操作都发生在新账号。

---

## 脚本清单

| 脚本 | 做什么 | 产物 |
|------|--------|------|
| `装SSH公钥.sh` | 给老账号实例装我方 SSH 公钥（**开通访问，只需跑一次**） | 目标机 `~/.ssh/authorized_keys` |
| `拉取三环境.sh` | **推荐入口**：一次拉三个环境的容器配置 + 数据库（bash，一次输口令跑完） | `备份/docker镜像/<env>/`、`备份/数据库/<env>/` |
| `拉取数据库.ps1` | 单环境数据库拉取（PowerShell 版，会逐次弹私钥口令） | `备份/数据库/<env>/` |
| `拉取docker-env.ps1` | 单环境容器配置拉取（PowerShell 版，同上） | `备份/docker镜像/<env>/` |
| `拉取S3.ps1` | 拉 S3 桶文件，可选回推到新账号 | `备份/s3/<桶>/` |
| `数据库隧道.sh` | **本机直连老环境数据库**（SSH 隧道到 EC2 上的容器库，**不经任何堡垒机**） | 本地端口 → 容器 5432 |
| `源环境.env` | 三台机器的 HOST/USER/KEY + AWS profile/桶清单（**gitignore**） | — |

---

## 一次性准备

1. `源环境.env` 已配好（三台 HOST/USER/KEY，私钥 `~/.ssh/wenchao`，passphrase 见 `deploy-env/密码.local.md`）。
2. 老账号 AWS 凭证：本机 profile 名是 **`css-client`**（身份 `arn:aws:iam::021213872872:user/Dev`，在 Administrators 组）。
   > 历史文档里写的 `css-src` 是**不存在的** profile 名，已在 `源环境.env` 里改正。
3. 新账号凭证：本机 **default** profile 就是新账号运维号 `css-api`（`582797602427`），无需切换。

---

## 操作 0 · 开通 SSH 访问（`装SSH公钥.sh`）

```bash
./装SSH公钥.sh dev            # 单个环境
./装SSH公钥.sh all            # dev + stage + preprod（幂等，已装过的跳过）
./装SSH公钥.sh dev ~/.ssh/别的钥.pub   # 指定公钥，缺省 ~/.ssh/wenchao.pub
```

**它解决什么问题**：dev / stage 原本只有客户自己的 key pair `css`（我方无私钥），SSH 直连 `Permission denied`；
这两台机器**没有 IAM instance profile、没被 SSM 托管**，所以 Session Manager 也走不通。

**怎么破的局**：用 **EC2 Instance Connect**——AWS 原生通道，把公钥临时（60 秒）推进实例授权列表，
脚本在这个窗口内 SSH 进去，把公钥**永久**追加到 `~/.ssh/authorized_keys`，之后就是普通 SSH。

前置：调用者需 `ec2-instance-connect:SendSSHPublicKey` 权限（`Dev` 用户在 Administrators 组，已具备）；
实例需预装 `ec2-instance-connect` 包（AWS 官方 Ubuntu AMI 默认有）；安全组 22 端口放行本机出口 IP（三台均已放行）。

**已执行（2026-08-03）**：dev ✅、stage ✅ 装入并复验通过；preprod 本就可登录。

> 🔒 **装上去的公钥不带任何个人标识**：只写「类型 + 密钥体」两段，`.pub` 尾部的 `用户名@机器名`
> 注释会被脚本剥掉（2026-08-03 要求，已同步清理 dev/stage 上已装条目；preprod 的条目本就无注释）。

---

## 操作 1 · 拉配置 + 数据库（`拉取三环境.sh`，推荐）

```bash
./拉取三环境.sh                      # = all all：三个环境的配置 + 数据库全拉
./拉取三环境.sh dev db               # 只拉 dev 的两个库
./拉取三环境.sh all env              # 只拉三个环境的容器配置
SSH_KEY_PASSPHRASE=xxx ./拉取三环境.sh   # 免交互（口令也可留空，脚本会提示输入一次）
```

**为什么另做 bash 版而不用同目录的 .ps1**：本机 Windows `ssh-agent` 服务是 **Disabled**（启用要提权），
而 `~/.ssh/wenchao` 带 passphrase——PowerShell 里的 `ssh.exe` 每次连接都弹口令，六次拉取要输六次。
bash 版在脚本内起 git-bash 自带的 ssh-agent（跑完自动 kill），**一次解锁跑完全程**。.ps1 保留作单环境手动使用。

### ⚠️ 关于"三个环境的 .env 文件"

**这三台机器磁盘上没有 `.env` 文件**（2026-08-03 全盘搜索确认，含隐藏文件）。
部署由 **GitLab Runner** 在临时目录 `/builds/css_new/css-backend` 里执行 `docker compose up`，
`.env` 是 CI 流水线生成的临时文件，**容器起来后即随工作目录一起删除**。

所以这三个环境的运行时配置，**唯一可得来源是运行中容器的注入环境变量**
（`docker inspect --format '{{range .Config.Env}}...'`）——脚本拉的就是它，每容器一个 `.env` 文件。
拿到的值与当时 CI 写进 `.env` 的值等价（compose 的 `env_file`/`environment` 最终都注入成容器环境变量）。

**已执行（2026-08-03）**：dev 20 个容器、stage 21 个、preprod 20 个，共 61 份配置。

### 数据库形态（三台一致）

| 容器 | 库 | dev | stage | preprod |
|---|---|---|---|---|
| `css-backend__db` | `postgres`（主库） | 83 MB / 154 表 | 86 MB / 154 表 | 46 MB / 146 表 |
| `css-backend__ocr-db` | `ocr_catalog`（OCR 库） | ~8 MB / 4 表 | ~8 MB / 4 表 | ~8 MB / 4 表 |

dump 直接经 SSH 管道回本地（**不在源服务器 /tmp 落盘**，不留痕不占盘），落地后校验 `PGDMP` 文件头。

### 拉取过程中的四个发现（都影响后续迁移判断）

**① dev/stage 的代码比 preprod 新**：`alembic_version` dev/stage = `e8f2a4b6c1d3`，preprod = `e1f2a3b4c5d6`。
判断"GitHub main 缺哪些迁移"时，基准应取 dev/stage 而非 preprod。

**② 机器名和镜像 tag 对不上，极易搞混**：

| 机器 | 跑的镜像 tag | 说明 |
|---|---|---|
| `css-dev` | `...:test-031567cb` | dev 机器跑的是 **test** 分支镜像 |
| `css-stage` | `...:dev-a3725957` | stage 机器跑的是 **dev** 分支镜像 |
| `css-preprod` | `...:preprod-a30cc99c` | 只有这台对得上 |

判断"某个环境实际在跑什么代码"时**不能看机器名**，要看镜像 tag。

**③ 三个环境的 `PASSWORD_SALT` 各不相同**（决定导入的用户能否用原密码登录）：

| salt 归属 | md5(salt) 前 12 位 | 迭代 | 算法 |
|---|---|---|---|
| 老账号 dev = stage | `cbfdc0b6e197` | 100000 | sha256 |
| 老账号 preprod | `3c6db5ab1a0b` | 100000 | sha256 |
| 我方 test | `c16208548ef3` | 100000 | sha256 |

这正是历史上"导入 preprod 用户后登录全挂"的根因——用户的 `password_hash` 是拿**原团队的 salt** 算的，
而我方 env 里是随机 salt。**现在三个环境的真实 salt 都在 `备份/docker镜像/<env>/css-backend__app.env` 里**：
若将来需要让导入用户沿用原密码，把对应环境的 salt 配进 `deploy-env/<env>/backend.env` 即可；
若继续用 `anonymize-db.sh` 统一口令（test 现在就是这样，`Test1234!`），则保持我方 salt 不变即可，无需理会。

**④ stage 比 dev 多两个开关**：`CONFIRMATION_CODE_VERIFICATION_ENABLED`、`CONTRACT_FIRST_STUBS_ENABLED`
（与 ② 一致——stage 跑的 dev 分支镜像更新）。除这两项外，三个环境的配置键名完全相同（116 项）。

---

## 操作 2 · 把备份载入新账号非生产 RDS

用 **`../环境运维执行脚本/05-数据库运维/restore-old-env-backup.sh`**（不是 `restore-dump-via-gw.sh`——
那个会覆盖正在用的 test/uat 库）：

```bash
bash ../环境运维执行脚本/05-数据库运维/restore-old-env-backup.sh all
bash ../环境运维执行脚本/05-数据库运维/restore-old-env-backup.sh --list   # 只看现有库
```

恢复成 `backup_<YYYYMMDD>_old_<源环境>_main` / `..._ocr` 六个**独立留档库**（库名一律英文，backup_ 前缀在最前）。
**已执行（2026-08-03）**：`backup_20260803_old_{dev,stage,preprod}_{main,ocr}`，
源库与备份库全表行数指纹逐字节一致（详见该脚本所在目录的 README）。

### 直连老环境数据库（`数据库隧道.sh`）

```bash
./数据库隧道.sh dev                  # localhost:5433 → dev 主库（库 postgres，用户 postgres）
./数据库隧道.sh stage ocr 5434       # localhost:5434 → stage OCR 库（ocr_catalog）
./数据库隧道.sh preprod main 5433 --check   # 只探测通不通，不驻留
```

与新账号 `05-数据库运维/db-tunnel.sh`（连私网 RDS，必须经堡垒机）不同：老环境的库跑在 EC2 自己的
docker 容器里、EC2 有公网 IP，**直连该机，不走堡垒机**。容器 5432 未发布到宿主机端口，
脚本先查容器 IP 再开 `-L` 隧道。密码在 `备份/docker镜像/<env>/css-backend__db.env` 的 `POSTGRES_PASSWORD`。
已实测（2026-08-03）：dev/stage/preprod 三条隧道 `--check` 全通。

---

## 操作 3 · S3 文件（`拉取S3.ps1`）

```powershell
.\拉取S3.ps1 -SizeOnly                              # 先只统计各桶大小/对象数
.\拉取S3.ps1                                         # 下载 源环境.env 的 SRC_S3_BUCKETS 全部桶
.\拉取S3.ps1 -Bucket chain-serve-test                # 只拉单桶
.\拉取S3.ps1 -PushToDst -DstBucket css-test-storage  # 下载后回推到新账号（需先建好目的桶）
```

手动等价（注意 profile 是 `css-client`）：

```bash
aws s3 ls  s3://chain-serve-test --recursive --summarize --human-readable --profile css-client --region eu-central-1
aws s3 sync s3://chain-serve-test "备份/s3/chain-serve-test" --profile css-client --region eu-central-1
```

---

## 迁移完整流程

1. `装SSH公钥.sh all` 开通访问（已完成）。
2. `拉取三环境.sh` 落地配置 + 数据库（已完成）；`拉取S3.ps1 -SizeOnly` 评估 S3 数据量。
3. `restore-old-env-backup.sh all` 把三环境数据载入新账号 RDS 做留档（已完成）。
4. 用 `备份/docker镜像/` 里的旧配置对照，把有效值填进 SSM Parameter Store `/css/<env>/backend.env`
   （唯一事实源；本地底稿 = 工作区根 `deploy-env/<env>/backend.env`）。**真实密钥迁移后建议全部轮换**。
5. 环境投产时才用 `restore-dump-via-gw.sh` 灌进 `css-<env>-main`，随后**必须**跑 `anonymize-db.sh` 脱敏。

> ⚠️ `备份/` 下全部产物（数据库 dump、容器配置、S3 文件）与 `源环境.env` 都含**真实凭证与真实个人数据**，
> 已在根 `.gitignore` 排除，切勿提交或外传。

---

## 可视化页面（老账号 021213872872 / eu-central-1）

1. **EC2 实例列表**：<https://eu-central-1.console.aws.amazon.com/ec2/home?region=eu-central-1#Instances:>
   - 三台源服务器：`css-dev`(i-072a709f0205514e3) / `css-stage`(i-02d75a88344591383) / `css-preprod`(i-08f640a82749cffdf)
   - 拉取前确认目标机 Running、公网 IP 与 `源环境.env` 一致。
2. **S3 桶列表**：<https://console.aws.amazon.com/s3/buckets> —— 桶名与对象数/大小，和 `-SizeOnly` 统计对照。
3. **本机落地产物** `C:\github-code\chain-serve\备份\`：`数据库\<环境>\`、`docker镜像\<环境>\`、`s3\<桶>\`。

## `migrate-s3-to-new.sh` — 老桶 → 新账号环境桶【跨账号流式增量同步】（2026-08-04 新增）

```bash
./migrate-s3-to-new.sh <test|uat|prod> [--dry-run] [--jobs N] [--src-bucket 桶] [--prefix 前缀]
```

与 `拉取S3.ps1` 的分工：那个是"全量下载到本地 `备份/s3/` 再可选回推"（要 7.5GB 磁盘、非增量）；
本脚本**流式直传不落盘 + 增量 + 幂等**，专为"临时迁移 → 约 20 天后彻底迁移再跑一次"设计。

- **增量**：逐对象比对 key+size，只传目标桶缺失/大小不同的；老环境期间新增的文件下次自动补上
- **不删除**：目标桶多出来的对象（新环境自产文件）绝不动，只做补齐
- **中断可续**：直接重跑
- **key 原样保留不重映射**：老对象 key 是 `eu-central-1/files/*`（老配置把桶名/区域填反的产物），
  新环境是 `us-east-1/*`，前缀不同可同桶共存 → 所以库里只需换 URL 域名前缀
  （`../环境运维执行脚本/05-数据库运维/rewrite-file-urls.sh`）
- 匿名 list 老桶被拒（只公开了对象读），故必须用老账号只读 profile；跨账号无法一条 `aws s3 sync` 直传，
  本脚本用双 session 流式转发解决
- 2026-08-04 实测规模：`chain-serve-test` **58118 对象 / 6.99 GB**（老 dev/stage/preprod 共用此桶）
