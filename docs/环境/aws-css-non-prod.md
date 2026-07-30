# AWS 群组文档：css-non-prod（非生产：test + uat）

> 状态（2026-07-29）：**网络/IAM 骨架、网关机、RDS `css-non-prod`、test/uat 两台应用机、两个 ALB、5 个 S3 桶、
> test/uat 的 CloudWatch 监控均已建成**；test 三栈已部署且数据已脱敏，uat 只建机未部署。
> 账号自带的**默认 VPC 已删除**（见 §1）。RDS 升配被 Free plan 拦截（见 §3）。
> 账号 `582797602427` / us-east-1。凭证隔离原则见 [../生产部署/03-CICD-GitHub-Actions.md](../生产部署/03-CICD-GitHub-Actions.md) §4.5。

## 1. 网络

> 网络与 IAM 骨架 **2026-07-28 已创建**（脚本：工作区 `docs/新aws账号/01-vpc/create-vpc.sh`、`docs/新aws账号/07-iam/create-iam.sh`，幂等可重跑）。
> 标签：网络骨架全部是跨环境共享资源，统一 `Group=css-non-prod` + **`CssEnv=css-shared`**（见 §8）。

| 资源 | 设计 | 资源 ID |
|------|------|---------|
| VPC `css-non-prod` | 10.20.0.0/16，DNS 主机名开启 | `vpc-014be109b904d6a07` |
| 公有子网 ×2 | 10.20.0.0/24（1a）、10.20.1.0/24（1b）；放网关机 | `subnet-05e2714c662a7a09a` / `subnet-08c98e86180963b12` |
| 私有子网 ×2 | 10.20.10.0/24（1a）、10.20.11.0/24（1b）；放 test/uat 应用机 + RDS | `subnet-04a93307191b196df` / `subnet-0ae9a401f7019cd69` |
| IGW + 公有路由表 | 0.0.0.0/0 → IGW | `igw-0aab6c7e645cf8d5e` / `rtb-0dc10ddb89b0b9a4b` |
| 私有路由表 | 0.0.0.0/0 → 网关机 ENI（网关机 `i-08b0ef319d08eae38` ✅ 已建） | `rtb-09e52c1f686601034` |
| S3 Gateway Endpoint | 免费，S3 流量不出 NAT | `vpce-0d9f563d331e2d8ee` |

> ✅ **默认 VPC 已于 2026-07-29 删除**（`docs/新aws账号/01-vpc/delete-default-vpc.sh`）：`vpc-0f1a28d652c598172`
> 及其 6 个子网、IGW、路由表、默认安全组、RDS `default` 子网组全部清掉。删它的理由：默认 VPC 打不了有意义的
> 环境标签（永远是合规例外），且不显式指定 VPC 时资源会误落进去（旧 test 机、旧 RDS 就是这么来的）。
> 现在账号里只有 `css-non-prod` 与 `css-prod` 两个自建 VPC。**可逆**：`aws ec2 create-default-vpc --region us-east-1`。

## 2. 服务器

| 机器 | 规格 | 子网 / 私网 IP | 职责 | 状态 |
|------|------|----------------|------|------|
| 网关机 `css-non-prod-gw` | t4g.micro（Amazon Linux 2023 arm64）+ EIP `3.225.148.166` | 公有 / 10.20.0.74 | **只剩两件事**：① 堡垒（22，SSH 唯一入口）② NAT（iptables masquerade）。~~③ nginx 反代~~ **2026-07-29 已停用并禁用**（ALB 接管）；instance profile `css-gw-non-prod`（SSM + 读 css-dbsync 桶 + 读 rds! secret），标签 `CssEnv=css-shared`——**不是部署目标** | ✅ `i-08b0ef319d08eae38` |
| `css-test-app` | m7i-flex.large（2C/8G，gp3 50G） | 私有 / **10.20.10.10** | test 三栈（`css-test-{infra,backend,frontend}`），标签 `CssEnv=css-test` | ✅ `i-0b3e73ed51811b69c`，已部署 |
| `css-uat-app` | m7i-flex.large（2C/8G，gp3 50G） | 私有 / **10.20.11.10** | uat 三栈，标签 `CssEnv=css-uat` | ✅ `i-00c635f52140cf035`，**已建机未部署** |

> 旧默认 VPC 的 test 机 `i-08e110b5a5425980d`（100.30.61.207）已于 2026-07-28 删除、EIP 已释放。
>
> **网关机改名（2026-07-29）**：Name 标签 `css-nonprod-gw` → **`css-non-prod-gw`**，EIP 的 Name 标签同步改为
> `css-non-prod-gw-eip`，IAM 角色 `css-gw-nonprod` → **`css-gw-non-prod`**（新建 → 换绑 instance profile → 删旧）。
> **实例 ID `i-08b0ef319d08eae38` 与 EIP `3.225.148.166` 都没变。**
>
> **SSH 一机一钥**（2026-07-29）：三台各有专属 ed25519 key pair `css-non-prod-gw` / `css-test` / `css-uat`，
> 私钥只在本机 `~/.ssh/<名>.pem`；每台 `authorized_keys` 另存个人公钥 `wenchao` 作第二通道。

## 3. 数据库

实例 **`css-non-prod`**（✅ 2026-07-28 已在新 VPC 建成，`docs/新aws账号/04-rds/create-rds.sh nonprod` 创建；旧默认 VPC 同名实例已删除）：

| 项 | 值 |
|----|-----|
| Endpoint | `css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com` |
| 引擎/规格 | PostgreSQL **16.14** / **db.t4g.micro**（1GB 内存），单 AZ ——⚠️ 计划升 **db.t4g.small**，见下方"升配"行 |
| Master 用户 | `postgres`（密码 Secrets Manager 托管，`rds!` secret） |
| 网络 | 私有子网、`--no-publicly-accessible`，SG 仅放行 app/网关 SG（仅内网访问） |
| 标签 | `Group=css-non-prod` + `CssEnv=css-shared`（实例与子网组都是 test/uat 共用） |
| 库 | `css-test-main` / `css-test-ocr` ✅ 已从 preprod 备份载入（含 pgvector）；`css-uat-main` / `css-uat-ocr` ⏳ 待建（`create-databases.sh`，ocr 库自动加 pgvector） |
| 升配 | ⚠️ **待办，被 Free plan 拦截**：近 7 天实测 CPU 平均 3.6%/峰值 29.7%（不是瓶颈）、**可用内存平均仅 146MB/峰值 224MB（真正的瓶颈）**、连接数峰值 27 → 结论升 `db.t4g.small`（2GB，~$24/月）即可，medium 属超配。执行时报 `FreeTierRestrictionError: This instance size isn't available with free plan accounts.`——**Free plan 下 RDS 只能用 db.t4g.micro**，需先升级账号 Paid plan；脚本 `docs/新aws账号/04-rds/resize-rds.sh` 已就绪，届时一条命令（会重启数据库，单 AZ 中断约 2-5 分钟） |
| 脱敏 | ✅ **`css-test-main` 已于 2026-07-29 脱敏**（`05-数据同步/anonymize-db.sh test`）：email 值前加 `1`、phone 值后加 `1`、所有 `password_hash` 统一为口令 **`Test1234!`**（pbkdf2_hmac sha256 + env 的 `PASSWORD_SALT` + 10 万次迭代）。实测残留 0 条、188 个账号哈希一致。uat 载入真实数据后同样必跑；prod 脚本拒绝执行 |

数据恢复走 `docs/新aws账号/05-数据同步/restore-dump-via-gw.sh`：本地 `pg_dump -Fc` 备份 → S3 中转桶 `css-dbsync-<账号>` → SSM 在网关机装 psql16、自取 Secrets Manager 密码、建库（+pgvector）、`pg_restore`、清理。⚠️ 数据库版本注意：导数据前核对源/目标 PG 大版本（本实例 PG16），`pg_dump`/`pg_restore` 客户端版本不得低于服务端大版本；跨大版本恢复前先在测试库演练。env 中 `POSTGRES_DB`、`OCR_*_URL` 使用新库名。

## 4. 安全组（2026-07-29 收口 + 改名后）

| SG | 入站 | 出站 | ID |
|----|------|------|-----|
| `css-non-prod-gw-sg` | `22 ← 221.214.0.190/32`（SSH 跳板）；`10.20.0.0/16` **全协议**（NAT 回程）。~~80 / 8080~~ **已撤销** | all | `sg-0f449992d538ac3b4` |
| `css-non-prod-app-sg`（test/uat 共用） | `22 ← gw-sg`；`80 ← alb-sg`。~~80 ← gw-sg~~ **已撤销**（Web 只收 ALB） | all（经网关 NAT） | `sg-0d06e029924989ee3` |
| `css-non-prod-rds-sg` | `5432 ← app-sg + gw-sg`（**仅内网**，RDS 不可公网访问） | — | `sg-0197c0db4578107ef` |
| `css-non-prod-alb-sg` | `80/443 ← 0.0.0.0/0`（`css-test` 与 `css-uat` 两个 ALB 共用） | all | `sg-0c7b0b571d74b1f2f` |

> ⚠️ **`10.20.0.0/16 全协议`那条不是给 SSH 的，别删**：test/uat 在私有子网、没有公网 IP，出网全靠网关机 NAT 转发，
> **回程流量必须放行**。删了它两台机器立刻断网（拉不了 ECR 镜像、连不上 SSM，部署与远程运维全废）。
>
> 收口脚本：`docs/新aws账号/12-alb/revoke-gw-proxy.sh nonprod`（同时经 SSM 停用并禁用网关机 nginx）。
> `01-vpc/create-vpc.sh` 已同步，重跑不会把 80/8080 加回来。

**改名（2026-07-29）**：这 4 个组原名 `css-nonprod-*`（`sg-0cb64524667184295` / `sg-0cfa6a7448f3bb95c` /
`sg-035acf1546045ba88` / `sg-0c8f420e1e46b5b4b`），已统一为带连字符的 `css-non-prod-*`，与 VPC / RDS / `Group` 标签一致。
**AWS 的 GroupName 与 Description 创建后不可修改**，所以是"新建同规则 SG → 双挂 → 金丝雀（uat）→ 切换 → 删旧"的零中断迁移，
脚本 `docs/新aws账号/01-vpc/rename-security-groups.sh`（`plan|apply|verify|canary|cutover|cleanup`），**旧 4 个已删除**。
删旧必须按依赖倒序 `rds → app → alb → gw`，否则 `DependencyViolation`。生产那 4 个（`css-prod-*`）本就合规，ID 未变。
同时清掉了旧默认 VPC 里两个零引用的死组 `css-non-prod-db-sg`(`sg-095c23f15e3ed642b`) 与
`css-non-prod-ec2-sg`(`sg-08e01c425f5f35359`)。

## 4b. ALB（每环境一个，名字=环境名）

2026-07-29 起 **每环境一个独立 ALB**，旧的共享 `css-nonprod-alb` 已删除，"uat 按 Host 头分流"的设计随之作废。

| ALB | DNS | 监听器 → 目标组 | 目标 | 状态 |
|-----|-----|-----------------|------|------|
| `css-test` | `css-test-524317374.us-east-1.elb.amazonaws.com` | `:80` → `css-test-fe-tg` | 10.20.10.10:80 | ✅ healthy，前端实测 **200** |
| `css-uat` | `css-uat-1366981991.us-east-1.elb.amazonaws.com` | `:80` → `css-uat-fe-tg` | 10.20.11.10:80 | ✅ 已建；uat 未部署故目标暂 **unhealthy**（正常） |

- ALB 与目标组都带 `Group=css-non-prod` + `CssEnv=css-<env>` 双标签；`idle_timeout=3600s`（WebSocket）。
- 脚本：`docs/新aws账号/12-alb/create-alb.sh <test|uat|prod> [域名]`；补 443 用 `CERT_ARN=...` 重跑。
- kafka-ui（8085）**故意不挂 ALB**（无认证 + 能读 2FA 验证码），只走堡垒机隧道。

## 4c. S3 桶（共 5 个，全部带账号后缀）

| 用途 | 桶名 | 访问身份 | 标签 |
|------|------|----------|------|
| test 应用存储 | `css-test-582797602427` | IAM 用户 `css-app-test` | `CssEnv=css-test` |
| uat 应用存储 | `css-uat-582797602427` | `css-app-uat` | `CssEnv=css-uat` |
| prod 应用存储 | `css-prod-582797602427` | `css-app-prod` | `CssEnv=css-prod` |
| **dev 本地开发直传** | `css-dev-582797602427` | `css-app-dev`（✅ **已生成 key**） | `CssEnv=css-dev` |
| DB dump 中转 | `css-dbsync-582797602427` | 网关机角色 `css-gw-non-prod`（只读） | `CssEnv=css-shared` |

纯名 `css-test` / `css-prod` 被**别的 AWS 账号**占用（S3 桶名是全球唯一命名空间，不分账号），故统一回退带账号后缀（uat 也重建成带后缀的名字，旧空桶 `css-uat` 已删）。
test 旧桶 `css-test-storage-582797602427` 的 **102 个对象已 `s3 sync` 迁入新桶**，`S3_STORAGE_BUCKET_NAME` 已更新并灌进 Parameter Store，**旧桶已用 `13-s3/retire-bucket.sh` 退役删除**。
dev 桶供本地开发直传真实 S3（原来连 localhost:9000 的 MinIO），密钥写在工作区 `deploy-env/dev/backend.env`（不入库）。
每个桶都配了阻断公共访问 + SSE-S3 + 版本控制 + 生命周期 + 最小 CORS。脚本 `docs/新aws账号/13-s3/create-s3.sh`（`dev` 需显式指定，不在 `all` 里）。

## 4d. 监控告警（CloudWatch，✅ 2026-07-29）

test / uat **各 9 条告警 + 1 个 Dashboard + 1 个 SNS 主题**（`css-test-alarms` / `css-uat-alarms`），
脚本 `docs/新aws账号/14-cloudwatch/create-monitoring.sh <env> [邮箱]`，资源带 `Group`+`CssEnv` 双标签。约 **$1/环境/月**。

- 告警覆盖：EC2（CPU>80% / 状态检查 / CPU 积分）、RDS（CPU / **可用内存<100MB** / 剩余存储<2GB / 连接数>80）、
  ALB（**无健康目标** / 5xx / P95 延迟>3s）。其中 `rds-memory-low` 与 `alb-no-healthy-target` 最有价值。
- ⚠️ **SNS 主题目前还没有任何订阅者**——告警会触发但没人收得到。补法：带邮箱重跑脚本，
  然后**必须点确认邮件里的链接**（状态从 PendingConfirmation 变 Confirmed 才算生效）。
- EC2 的内存/磁盘使用率**不在里面**（宿主机看不到客户机内部），要监控得装 CloudWatch Agent（`--with-agent`，+$0.6/月/机）。
- ⏳ **日志收集（CloudWatch Logs）仅有方案未执行**——见 `14-cloudwatch/README.md` 后半（awslogs 驱动为主、Agent 兜底系统日志，约 +$6.3/月，务必设保留期）。

## 5. IAM（本群组专属，与 prod 群组完全独立）

✅ 已创建（OIDC provider：`arn:aws:iam::582797602427:oidc-provider/token.actions.githubusercontent.com`）：

| 主体 | 名称 | 权限 |
|------|------|------|
| CI/CD 角色（OIDC） | `css-deploy-test` / `css-deploy-uat` | ECR push；SSM send-command 限 `CssEnv=css-test|css-uat` 标签实例；参数 `/css/test/*` 或 `/css/uat/*`；uat 加 RDS 快照；信任两仓库对应分支与 GitHub Environment |
| 实例角色（含 instance profile） | `css-ec2-test` / `css-ec2-uat` | AmazonSSMManagedInstanceCore + ECR 只读 + 读本环境参数 |
| 应用 S3 用户 | `css-app-test` / `css-app-uat`（+ 本地开发用的 `css-app-dev`） | ✅ 三者均已挂内联策略 `css-app-<env>-s3`：桶级 `ListBucket`/`GetBucketLocation`/`ListBucketMultipartUploads` + 对象级 `PutObject`/`GetObject`/`DeleteObject`/`AbortMultipartUpload`/`ListMultipartUploadParts`，**Resource 精确到本桶 ARN**，跨桶无权。**key：只有 `css-app-dev` 生成了**（写在 `deploy-env/dev/backend.env`）；test/uat **暂不生成**（避免闲置凭证），用时 `07-iam/create-app-s3-user.sh <env> --new-key`，AK/SK 只进本环境 Parameter Store |
| 网关机 instance profile | `css-gw-non-prod`（2026-07-29 由 `css-gw-nonprod` 改名重建，旧角色与 profile 已删） | SSM 托管核心 + 读 S3 中转桶 `css-dbsync-*` + 读 RDS `rds!` secret（Secrets Manager）；挂它的网关机标签为 `CssEnv=css-shared`（**不是部署目标**） |

> 旧默认 VPC test EC2（`i-08e110b5a5425980d`，角色 `css-non-prod-ec2-role`）曾作为过渡期部署目标，**已于 2026-07-28 删除**；CI/CD 部署目标改为新 VPC 待建的应用机。

## 6. 配置与密钥

Parameter Store（SecureString）：`/css/test/backend.env`、`/css/test/frontend.env`、`/css/uat/backend.env`、`/css/uat/frontend.env`。test 已灌入（本地底稿：工作区根 `deploy-env/test/`，与两代码仓库同级，不入库）；uat 以 `deploy-env/uat/*.example` 为底稿填值。耦合键（`API_KEY==VITE_X_API_KEY` 等）由 CI 校验。（EC2 上 `/opt/css-cicd/env/<env>/` 为部署时的运行时渲染路径，与本地底稿无关。）

## 7. 访问速查

网关 EIP = `3.225.148.166`。访问三条铁律：SSH 只经堡垒机（网关机）；**Web 只经本环境 ALB**；RDS 仅内网。

```
test 页面   http://css-test-524317374.us-east-1.elb.amazonaws.com/     （公网可达，ALB）
uat  页面   http://css-uat-1366981991.us-east-1.elb.amazonaws.com/     （ALB 已就绪，等 uat 部署）
SSH        ssh -i ~/.ssh/css-test.pem -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' ec2-user@10.20.10.10
RDS        ssh -i ~/.ssh/css-non-prod-gw.pem -N -L 5433:css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432 ec2-user@3.225.148.166 → 本地 psql localhost:5433
kafka-ui   ssh -i ~/.ssh/css-non-prod-gw.pem -N -L 8085:10.20.10.10:8085 ec2-user@3.225.148.166 → http://localhost:8085
```

> ~~`http://3.225.148.166/`、`:8080`~~ 这两个网关机反代地址 **2026-07-29 已失效**（过渡通道已收，nginx 已停用禁用）。

## 8. 标签规范（2026-07-29 全量落地）

所有资源两个标签：`Group=css-non-prod` + `CssEnv`。

| CssEnv | 用于 |
|--------|------|
| `css-test` / `css-uat` | **环境专属**资源：应用机、各自的 ALB 与目标组、S3 应用桶、（将来的）环境专属卷 |
| **`css-shared`** | **跨环境共享**资源：VPC、子网、路由表、IGW、S3 端点、安全组、网关机及其 EIP、RDS 实例与子网组、`css-dbsync` 中转桶 |

> ⚠️ **共享资源为什么必须是 `css-shared`**：IAM 的 `ssm:SendCommand` 条件、`09-ssm-run-command/run.sh` 与 `deploy-env.sh`
> 都按 `CssEnv=css-<env>` **定位部署目标机**。给网关机（或 VPC/安全组）打 `css-test`，它就会被 test 的部署命令选中
> → 往错误的机器上发部署。`css-shared` 既满足"人人两标签"，又不会被任何环境的部署逻辑命中。

存量补打：`docs/新aws账号/tag-all-resources.sh`（幂等，支持 `--dry-run`），2026-07-29 已执行。
新建资源无需补打——`01-vpc` / `04-rds` / `06-ec2`(gateway) / `12-alb` / `13-s3` 的创建脚本已内置双标签。
