# 09-远程执行与手动部署（原 09-ssm-run-command）—— SSM 命令通道 + EC2 端 deploy.sh 完整手册

SSM Run Command 是 CI/CD 从 GitHub 通向（私网）EC2 的命令通道：**不开 22 端口、不用 pem、无需任何入站规则**（EC2 上的 SSM Agent 主动向 AWS 出站长连接）。本文覆盖：脚本用法、机器前置配置、可视化页面、SSM 送达后在机器上执行的 **deploy.sh 全手册**、**配置体系（deploy-env ↔ Parameter Store）**、以及常用运维命令速查。具体值见 [../运维访问速查.local.md](../运维访问速查.local.md)。

## 脚本清单

### `setup-ssm.sh` — 把一台 EC2 配置成 SSM Run Command 可达的部署目标（挂实例角色 + 打 Environment 标签 + 验证 Online）

```bash
./setup-ssm.sh <test|uat|support-ref|support-demo|support-sync|prod> <instance-id>    # 环境名 + 目标实例 id
./setup-ssm.sh test i-0cb9b69b9eb19a9aa         # 给 test 机补配/排查 SSM 可达性
```

- 幂等：机器没角色→挂 `css-ec2-<env>`；已挂其他角色→不替换，改为给该角色补挂 SSM 托管策略 + `/css/<env>/*` 参数读取；最后打 `Environment=css-<env>` / `EnvironmentGroup` 标签并等待 Online（最长 5 分钟，失败退出非 0）。
- 基本只用于排查（SSM 不可达时）；css-terraform `ec2` stack 建的机器已自带角色与标签，无需再跑。

### `run.sh` — 经 SSM Run Command 在目标环境 EC2 上执行任意命令（免 SSH/22/pem），等待完成并回显输出

```bash
./run.sh <test|uat|support-ref|support-demo|support-sync|prod> '<shell 命令>'                          # 目标机按标签 Environment=css-<env> 且 SSM Online 定位
./run.sh test 'docker ps --format "{{.Names}} {{.Status}}"'      # 查看 test 环境三栈容器状态
```

- 命令经 JSON 安全编码，支持引号/多行/特殊字符；最长等 20 分钟，失败退出非 0。与 Backend 仓库 CI 用的 `deploy/aws/ssm-run.sh` 同源。

### `deploy-env.sh` — 手动部署一个环境（CI 之外的兜底/回滚入口；日常部署已由 CI 自动执行）：打包 Backend 仓库 deploy/{compose,config,bin} → 经 SSM 上传到目标机 /opt/css-cicd/ → 执行 deploy.sh

```bash
./deploy-env.sh <test|uat|support-ref|support-demo|support-sync|prod> [stack] [image_tag]   # stack: all(默认)|core(=infra+backend)|infra|backend|frontend
./deploy-env.sh test                                  # 全量部署 test（缺省用浮动 <env> tag，即最近一次 CI 推送）
./deploy-env.sh test backend test-v12                 # 只部署后端并回滚/固定到不可变版本 tag
./deploy-env.sh test migrate                          # 数据库迁移（特殊 stack 值，执行 alembic upgrade head）
```

- 部署 prod 前要求手输 `prod` 二次确认；机器端 deploy.sh 的完整行为（渲染 env → pull → up → 冒烟 → 清理）见下文第四节。

### `ec2-power.sh` — 停机 / 启动 / 查看某环境的应用 EC2（暂停不常用环境省钱；stopped 实例只计 EBS 费）

```bash
./ec2-power.sh <stop|start|status> <env> [env ...]           # env: test|uat|support-ref|support-demo|support-sync|prod
./ec2-power.sh stop support-ref support-demo support-sync      # 2026-09-04：暂停三台 support 机
./ec2-power.sh start support-demo                              # 恢复；容器随机自起，三栈约 2 分钟内可用
```

- `stop` 先关闭该环境全部 `css-<env>-*` 告警动作（否则 `alb-no-healthy-target`/`ec2-status-check` 翻 ALARM 发邮件）再停机并等待 stopped；`start` 启动、等状态检查通过后再恢复告警动作。
- 实例按 `Name=css-<env>-app` 定位；不动 RDS/ALB，私网 IP 不变；停机期间该域名 5xx、CI 部署因 SSM 不 Online 会失败；prod 需手输 `prod` 二次确认。

## 二、工作原理与机器前置

```
workflow / 本机（已持 css-deploy-<env> 或管理员凭证）
  └─ run.sh <env> '<命令>'
       ① describe-instance-information：找 标签 Environment=css-<env> 且 Ping=Online 的实例
       ② send-command（文档 AWS-RunShellScript，root 身份执行）
       ③ 每 5s 轮询直到终态 → 回显 stdout/stderr，失败退出非 0 → workflow 红
```

权限收口在 IAM：`css-deploy-<env>` 的 `ssm:SendCommand` 带条件 `ssm:resourceTag/Environment=css-<env>`——**test 的流水线在 IAM 层面就发不到 uat/prod 的机器**。

**为什么网关机的 `Environment` 必须是 `css-shared`**：`run.sh`/`deploy-env.sh` 用 `--filters "Key=tag:Environment,Values=css-<env>"` 定位部署目标机，IAM 条件也按同一标签放行。网关机 `css-non-prod-gw` 若打成 `css-test`，就会被 test 的部署命令选中——deploy.sh 跑到网关机上去。打 `css-shared`（跨环境共享资源专用值）既满足"每资源必有 Group+Environment 标签"，又永远不会被任何环境的部署命中；成本分摊上这部分（VPC/子网/网关机/RDS 实例本身等）是 test/uat 共担的基础设施。

**每台应用机的前置（两处，新机一次性；控制台路径）**：
1. **实例角色**：EC2 → Instances → 勾选实例 → **Actions → Security → Modify IAM role** → 选 `css-ec2-<env>`（角色含 SSM 托管策略 + ECR 只读 + 读本环境参数）；
2. **标签**：实例页 **Tags** 页签 → `Key=Environment, Value=css-test|css-uat|css-prod` + `Key=EnvironmentGroup, Value=css-non-prod|css-prod`（值必须带 `css-` 前缀，setup-ssm.sh 会自动打）。
3. 机器必须能**出站**（私网机器经网关机 NAT / NAT 网关）；角色刚变更后 Agent 刷新凭证可能要几分钟。

验证就绪：

```bash
aws ssm describe-instance-information --filters "Key=tag:Environment,Values=css-test" --query "InstanceInformationList[].{id:InstanceId,ping:PingStatus}" --output table
```

## 三、可视化页面

| 看什么 | 在哪 |
|--------|------|
| **命令执行历史**（每次部署都有记录，含 deploy.sh 完整输出） | Systems Manager → **Run Command** → Command history：`https://us-east-1.console.aws.amazon.com/systems-manager/run-command/complete-commands?region=us-east-1`，点 Command ID → 选实例 → Output |
| 哪些机器 SSM 在线 | **Fleet Manager**：`https://us-east-1.console.aws.amazon.com/systems-manager/fleet-manager/managed-nodes?region=us-east-1`（Ping status 应为 Online） |
| 网页版终端上机（代替 SSH） | **Session Manager** → Start session：`https://us-east-1.console.aws.amazon.com/systems-manager/session-manager?region=us-east-1`；命令行 `aws ssm start-session --target <实例id>` |
| 机器的角色/标签 | EC2 实例页 → Security 页签（IAM Role）、Tags 页签（Environment/Group） |

与堡垒机的关系：部署**不经过堡垒机**；堡垒机 `css-non-prod-bastion`（原名 css-non-prod-gw，EIP 3.225.148.166）是给人用的（SSH 跳板、psql 隧道）。SSM 与堡垒机互为备份通道。

## 四、SSM 送达后：EC2 端 deploy.sh 手册

### 脚本在哪

| 位置 | 说明 |
|------|------|
| 源码 | Backend 仓库 `deploy/bin/deploy.sh`（改它=改部署行为，走分支流程经 test 验证） |
| EC2 上 | `/opt/css-cicd/bin/deploy.sh` —— **每次 `deploy-env.sh`/CI 部署自动上传刷新**，与仓库同版本 |

配置从哪来：deploy.sh 每次部署前自动把 Parameter Store 的 `/css/<env>/backend.env` 渲染成机器上的 `/opt/css-cicd/env/<env>/backend.env`——**配置体系详见下文第五节**。

### 用法

```
/opt/css-cicd/bin/deploy.sh <test|uat|support-ref|support-demo|support-sync|prod> [action] [stack] [image_tag]
```

| 参数 | 取值 |
|------|------|
| action | `deploy`(默认) / `up` / `down` / `pull` / `migrate` / `ps` / `logs` / `restart` / `pytest`(仅test) / `render-env` |
| stack | `all`(默认) / `core`(=infra+backend) / `infra` / `backend` / `frontend` |
| image_tag | 不可变版本 tag 如 `test-v12`（CI 每次发布自增；手动推送为 `<env>-manual-<sha7>`）；缺省用浮动 `<env>` tag |

**`deploy` 的完整行为**：渲染 env → ECR 登录 → 逐栈 pull + up → 冒烟（backend `:8080/api/docs`、frontend `:80/`，重试 2 分钟）→ `docker image prune -f` → 写 `.last_good_<env>`。冒烟失败退出非 0 → CI 红。
`deploy`/`pull`/`migrate`/`up`/`restart` 都会先自动 render-env，所以**改完参数后单跑 `restart` 也会带上新配置**。

### 人工上机的典型操作

```bash
cd /opt/css-cicd
./bin/deploy.sh test ps                            # 三栈容器状态
./bin/deploy.sh test logs backend                  # 后端最近 200 行日志
./bin/deploy.sh test restart                       # 改完参数手动生效（自动重渲染 env，不重新 pull）
./bin/deploy.sh test deploy frontend test-v12      # 手动回滚前端到指定版本
cat .last_good_test                                # 上次成功部署的 tag
```

### 新机器初始化

机器由 css-terraform `<env>/ec2` stack 创建/重建（user_data 自动装 docker+compose，角色/标签已含）→ 等 SSM Online → 跑一次 `deploy-env.sh <env>`（或 Backend workflow）即完成 bundle 上传 + 首次部署。机器即"牲口"，重建成本≈半小时（重建流程见 css-terraform CLAUDE.md §十五-E）。

## 五、deploy-env 与 Parameter Store：配置到底存在哪、怎么改

配置有三份"形态"，职责不同，**只有 Parameter Store 是 AWS 侧的唯一事实源**：

| 形态 | 位置 | 角色 |
|------|------|------|
| 本地底稿 | 工作区根 `deploy-env/<env>/{backend,frontend}.env` | 编辑入口。**不入任何 git 仓库**（工作区 `.gitignore` 按 `*.env` 忽略，只放行 `*.example`） |
| **唯一事实源** | SSM Parameter Store `/css/<env>/backend.env`、`/css/<env>/frontend.env` | 整份 env 文件作为**一个参数的值**存放，SecureString 加密。backend.env 早已超 Standard 的 4KB 上限，用 **Advanced 层**（$0.05/参数/月，**上限 8192 字符**）。⚠️ **2026-08-22 实测 `/css/test/backend.env` = 8118 字符，只剩 74 字符余量**（uat 8129）——加新键前必须先精简注释。量长度用 `aws ssm get-parameter --name /css/<env>/backend.env --with-decryption --query 'length(Parameter.Value)'`，**不能用 `wc -m`**（Git Bash 下它数的是字节，中文注释会算多） |
| 机器渲染件 | EC2 `/opt/css-cicd/env/<env>/backend.env`（chmod 600） | deploy.sh 每次部署自动从 Parameter Store 拉取重写，compose 用 `--env-file` 读它。**手改会被下次部署覆盖** |

完整链路：

```
deploy-env/<env>/backend.env                    ← 本地底稿（在这里编辑）
   │  bash docs/环境运维执行脚本/11-parameter-store/put-params.sh <env>
   ▼
SSM Parameter Store /css/<env>/backend.env      ← 唯一事实源（SecureString 加密）
   │  deploy.sh 部署/重启时 aws ssm get-parameter --with-decryption
   │  （实例角色 css-ec2-<env> 只读 /css/<env>/*，跨环境读不到）
   ▼
EC2 /opt/css-cicd/env/<env>/backend.env         ← 渲染件（chmod 600）
   │  docker compose --env-file
   ▼
容器进程环境变量
```

### 我如何增加/修改一条配置（后端）

| 步 | 操作 | 命令 |
|----|------|------|
| 1 | 编辑本地底稿，加一行 `NEW_KEY=value` | 改 `deploy-env/test/backend.env` |
| 2 | 上传到 Parameter Store（整份覆盖） | `bash docs/环境运维执行脚本/11-parameter-store/put-params.sh test` |
| 3 | 重新部署使生效（重启容器即可，**不用重建镜像**） | `bash docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh test core` |
| 4 | 验证机器上已渲染 | `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'grep -n "^NEW_KEY=" /opt/css-cicd/env/test/backend.env'` |

- ⚠️ **例外：前端 `VITE_*` 是构建期烤入镜像的**。改 `deploy-env/<env>/frontend.env` 后除 put-params 外，必须**重新构建前端镜像**（重跑前端 CI workflow，或 `bash docs/环境运维执行脚本/03-本地构建推送镜像/push-ecr.sh <env>`），再 `deploy-env.sh <env> frontend`——只重启不生效。
- ⚠️ 耦合键成对改：`API_KEY`==`VITE_X_API_KEY`（一个在 backend.env、一个在 frontend.env）、`CATALOG_OCR_API_KEY`==`OCR_API_KEY`；`PASSWORD_SALT` 迁移必须原样搬运。
- **dev 环境不走 Parameter Store**：`deploy-env/dev/backend.env` 由本地 compose 直接 `--env-file` 读（入口 `.\deploy\windows\本地dev.ps1`），改完 restart 即生效。
- 在控制台直接 Edit 参数值也行（见下节），但会与本地底稿失联——下次谁跑 put-params 就把控制台改动覆盖回去。**推荐永远从本地底稿走**。

### Terraform 纳管说明（2026-07-30）

- 参数的【壳】（名称/类型/tier/标签）由 css-terraform 管理（uat 已建壳，test 暂不纳管——存量参数含密钥不 import）；
  参数的【值】永远不进 Terraform——你自己用控制台改、aws cli `put-parameter --overwrite`、
  或本目录旁的 put-params.sh 推送均可，Terraform 不会产生任何 diff（壳上有 ignore_changes[value]）。
- ⚠️ 唯一别动的是壳属性（tier / KMS key）：改壳会让 Terraform 用占位值重写参数，真值会丢。
- 标签键 2026-07-30 已切换：`Environment`（原 CssEnv）+ `EnvironmentGroup`（原 Group），
  本目录脚本与 IAM 条件已同步更新。

## 六、在 AWS 控制台哪里看这些配置

| 看什么 | 在哪 / 怎么看 |
|--------|--------------|
| 参数列表 | Systems Manager → **Parameter Store**：`https://us-east-1.console.aws.amazon.com/systems-manager/parameters?region=us-east-1` → 点 `/css/test/backend.env` |
| **参数明文** | 参数详情页 Value 默认隐藏 → 点 **Show decrypted value**。它是 SecureString **加密存储**的，你能看到明文是因为管理员身份有 `kms:Decrypt`；EC2 实例角色只能解密本环境的 `/css/<env>/*` |
| **修改历史** | 参数详情页 **History** 页签：每次 put-params/Edit 生成一个版本，可逐版本对比、复制旧值回滚。⚠️ **历史版本会永久保留旧值**——密钥轮换后旧密钥仍躺在历史版本里，要彻底清除只能删参数重建 |
| 机器上渲染出的那份 | `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'cat /opt/css-cicd/env/test/backend.env'`（**含全部密钥慎用**，且输出会留在 Run Command 历史里） |

## 七、常用运维命令速查表

以下命令都在工作区根目录（git-bash）直接执行，`test` 可换成 `uat|prod|support-ref|support-demo|support-sync`（新账号现有 7 个环境，其中 `dev` 只在本机跑、无 EC2）：

| 干什么 | 命令 |
|--------|------|
| 看三栈容器状态 | `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'docker ps --format "{{.Names}} {{.Status}}"'` |
| 看后端日志（最近 200 行） | `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test '/opt/css-cicd/bin/deploy.sh test logs backend'` |
| 全量部署（最新浮动 tag） | `bash docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh test` |
| 只部署后端 | `bash docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh test backend` |
| 回滚到指定版本 | `bash docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh test backend test-v12` |
| 数据库迁移 | `bash docs/环境运维执行脚本/09-远程执行与手动部署/deploy-env.sh test migrate` |
| 改配置后重启生效 | `put-params.sh test` 后 `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test '/opt/css-cicd/bin/deploy.sh test restart'` |
| 上传配置到 Parameter Store | `bash docs/环境运维执行脚本/11-parameter-store/put-params.sh test` |
| 看机器上生效的配置（含密钥慎用） | `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'cat /opt/css-cicd/env/test/backend.env'` |
| 看上次部署成功的 tag | `bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'cat /opt/css-cicd/.last_good_test'` |
| 终端上机（免 SSH） | `aws ssm start-session --target i-0cb9b69b9eb19a9aa`（test 机；uat=`i-0f90c5c061d640a27`，堡垒机=`i-08b0ef319d08eae38`） |
| SSH 上机（备用通道） | `ssh -i deploy-env/ssh/css-test.pem -o ProxyCommand='ssh -i deploy-env/ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' ec2-user@10.20.10.10` |

### 本机连 RDS（数据库在私有子网、不可公网访问）

```bash
# ①【推荐】SSH 端口转发经堡垒机（保持此窗口开着），本机 psql/DBeaver/Navicat 连 localhost:5433
ssh -i deploy-env/ssh/css-non-prod-gw.pem -N -L 5433:css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com:5432 ec2-user@3.225.148.166
psql -h localhost -p 5433 -U postgres -d css-test-main
# （~/.ssh/config 配了 Host css-gw 后可简写：ssh -N -L 5433:<rds-endpoint>:5432 css-gw）

# ②【免密钥】SSM 端口转发：不开 22、不用密钥、有完整审计日志；需本机装 session-manager-plugin（当前未装）
aws ssm start-session --target i-08b0ef319d08eae38 --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com"],"portNumber":["5432"],"localPortNumber":["5433"]}'

# ③【机器上直连】一次性 SQL，经 SSM 在应用机上用 docker 跑 psql（日常账号推荐 css_dev，密码见 运维访问速查.local.md）
bash docs/环境运维执行脚本/09-远程执行与手动部署/run.sh test 'docker run --rm -e PGPASSWORD=<密码> postgres:16 psql -h css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com -U css_dev -d css-test-main -c "select 1"'

# master(postgres) 仅运维用：Secrets Manager 托管、每 7 天自动轮换，用时现取（应用已切 css_app_<env>，不受轮换影响）
aws secretsmanager get-secret-value --region us-east-1 \
  --secret-id $(aws rds describe-db-instances --region us-east-1 --db-instance-identifier css-non-prod --query 'DBInstances[0].MasterUserSecret.SecretArn' --output text) \
  --query SecretString --output text
```

**为什么不能本机直连**：RDS 无公网 IP（`--no-publicly-accessible`），安全组 `css-non-prod-rds-sg` 只放行来自各环境 app-sg（`css-test-app-sg`/`css-uat-app-sg`）与堡垒机 `css-non-prod-bastion-sg` 的 5432，本机 IP 根本不在其中。强行改成 publicly-accessible 是错误做法（数据库直接暴露公网），一律走上面三条路。完整指南见 [../本地连接数据库.md](../本地连接数据库.md)。

## 八、常见问题

| 现象 | 处理 |
|------|------|
| 实例不在 describe-instance-information 里 | 角色没挂 / 机器出不了网（查私有路由 NAT）/ Agent 没跑（Session 上机 `systemctl status amazon-ssm-agent`） |
| send-command 报 AccessDenied | 用错环境凭证，或目标机标签与环境不符——IAM 条件按设计拦截 |
| 命令超时（最长 20 分钟） | 首次 pull 大镜像可能超，重跑一次（层已缓存会快） |
| deploy 冒烟失败 | 看 Run Command Output / GitHub job 日志定位哪个栈没起来 |
| 改了配置没生效 | 检查是否漏了 put-params（机器渲染的是 Parameter Store 里的值，不是你本地文件）；前端 `VITE_*` 要重建镜像 |

## 九、注意点

- EC2 上的 `/opt/css` 是旧手动链路（部署包时代）残留，已退役可删；应急手动操作 = 上机执行 `/opt/css-cicd/bin/deploy.sh`；
- `down` infra 栈会丢 kafka 未消费的 2FA 验证码（kafka 不落盘，设计如此）；
- prod migrate 前 workflow 自动打 RDS 快照，但**人工核对 `alembic_version` 在代码迁移链上**不能省；
- 回滚入口优先走 `deploy-env.sh <env> <stack> <旧tag>`（可用 tag 看 ECR 或 `.last_good_<env>`）；
- 状态（2026-08-22）：新账号现有 **7 个环境**——`test` / `uat` / `prod` / `support-ref` / `support-demo` / `support-sync` 六个在 AWS 上跑（各自应用机三栈已部署、SSM Online），`dev` 只在本机跑。**prod 已于 2026-08-07 建成三栈，2026-08-22 完成产品正式切换**（域名 `chain-serve.com`）。角色/标签由 Terraform 管理，无需再跑 setup-ssm。具体实例 ID/地址见 `css-terraform/环境实况/` 与 `../运维访问速查.local.md`。
  > 以下为 2026-07-31 时的记录：`css-test-app`（i-0cb9b69b9eb19a9aa）三栈已部署、SSM Online；`css-uat-app`（i-0f90c5c061d640a27）已建机未部署（两台 2026-07-30 由 css-terraform 重建，实例 ID 变更）；prod 应用机等 Paid plan（`enable_prod_compute` 门控）。
