# 06-ec2 —— 服务器（应用机 / 网关堡垒机）与 SSH 密钥 💰

> ⚠️ **2026-07-30 起本目录创建类脚本已删除**（本 README 保留作资源说明/运维参考）：机器创建/删除已由 css-terraform 接管（network 的网关机 + 各环境 ec2 stack）：create-app-ec2.sh/create-gateway.sh/delete-ec2.sh 废弃；setup-ssh-key.sh、create-instance-keys.sh 仍有效（密钥不进 TF）。
> 资源变更一律走 css-terraform 仓库（规范见其 CLAUDE.md）。

四个脚本，覆盖"建机 → 装密钥 → 删机"全流程。**访问铁律**：应用机全在私有子网、无公网 IP，
SSH 只能经堡垒机跳，Web 只能经 ALB（见 [12-alb](../12-alb/README.md)）。

| 脚本 | 作用 | 计费 |
|------|------|------|
| `setup-ssh-key.sh [公钥文件] [实例名/ID …]` | 把本机公钥导入为 EC2 key pair（新建实例引用）；对**已存在**的实例经 SSM 追加到 `authorized_keys`（已建机器无法事后绑 key pair，只能这样补） | 免费 |
| `create-instance-keys.sh [个人公钥] [css-test\|css-uat\|css-non-prod-gw]` | **一机一钥**：为每台机器创建专属 ed25519 key pair、私钥落到本机 `~/.ssh/<名>.pem`，再经 SSM 把「该机专属公钥 + 个人公钥 wenchao」一起写进 `authorized_keys`（幂等去重） | 免费 |
| `create-app-ec2.sh <test\|uat\|prod> [type] [keypair]` | 建应用机：私有子网、固定私网 IP、无公网 IP、挂 `css-ec2-<env>` 实例角色、user-data 装 docker+compose、打标签 `CssEnv=css-<env>`（SSM 部署按此定位） | 💰 |
| `create-gateway.sh <nonprod\|prod> [keypair]` | 非生产=网关机（**堡垒 + NAT 两件事**，2026-07-29 起不再安装 nginx 反代）并把私有路由指向它；生产=纯堡垒机 + 托管 NAT 网关。同时创建并挂载运维 profile `css-gw-non-prod` / `css-gw-prod`（旧名 `css-gw-nonprod` 会被脚本自动换绑并删除）；打标签 `Group` + `CssEnv=css-shared` | 💰 |
| `delete-ec2.sh <实例名或ID> yes` | 删实例 + 释放其 EIP。拒绝删网关/堡垒机（防误伤出网与运维通道） | — |

## 怎么用

```bash
cd docs/新aws账号/06-ec2

# 1) 密钥（只需一次；本机 ~/.ssh/wenchao.pub → key pair "wenchao"，并补装到已运行的网关机）
./setup-ssh-key.sh ~/.ssh/wenchao.pub css-non-prod-gw

# 2) 网关/堡垒机（非生产已建；prod 待 Paid plan）
./create-gateway.sh nonprod wenchao

# 3) 应用机（默认 m7i-flex.large 2C/8G；prod 默认 c5.xlarge）
./create-app-ec2.sh test
./create-app-ec2.sh uat
./create-app-ec2.sh prod m7i-flex.xlarge     # 规格可传第二参覆盖

# 4) 一机一钥（建机后执行；三台全做，或只补某一台）
./create-instance-keys.sh                          # 默认个人公钥 ~/.ssh/wenchao.pub
./create-instance-keys.sh ~/.ssh/wenchao.pub css-uat

# 5) 退役
./delete-ec2.sh css-uat-app yes
```

## 当前实况（2026-07-29）

| 名称 | 实例 ID | 规格 | 地址 | 标签 `CssEnv` | 状态 |
|------|---------|------|------|---------------|------|
| `css-non-prod-gw` | i-08b0ef319d08eae38 | t4g.micro | EIP **3.225.148.166** / 10.20.0.74 | `css-shared` | ✅ **只剩堡垒(22) + NAT**；nginx 过渡反代已停用禁用（`12-alb/revoke-gw-proxy.sh`）。2026-07-29 Name 标签由 `css-nonprod-gw` 改为现名（实例 ID / EIP 均未变） |
| `css-test-app` | i-0b3e73ed51811b69c | m7i-flex.large | 10.20.10.10（无公网） | `css-test` | ✅ 三栈已部署，入口 ALB `css-test` |
| `css-uat-app` | i-00c635f52140cf035 | m7i-flex.large | 10.20.11.10（无公网） | `css-uat` | ✅ 已建机，**未部署**（按要求）；ALB `css-uat` 已建 |
| `css-prod-app` / `css-prod-bastion` | — | — | 规划 10.10.10.10 | `css-prod` / `css-shared` | ⏳ 等 Paid plan |

> 网关机/堡垒机的 `CssEnv` **必须是 `css-shared`**：`ssm:SendCommand` 的 IAM 条件与 `run.sh`/`deploy-env.sh`
> 按 `CssEnv=css-<env>` 定位部署目标机，打成 `css-test` 会让网关机被 test 的部署命令选中。

## SSH 密钥（一机一钥，2026-07-29）

**凭证不跨机复用**：每台机器一把**专属** EC2 key pair（ed25519，无 passphrase），私钥只在本机；
同时每台的 `authorized_keys` 里**额外**保留个人公钥 `wenchao` 作为通用/应急第二通道。由 `create-instance-keys.sh` 一键建齐。

| 机器 | 专属 key pair | 本机私钥 | 第二通道 |
|------|---------------|----------|----------|
| `css-test-app` | `css-test` | `~/.ssh/css-test.pem` | 个人公钥 `wenchao` |
| `css-uat-app` | `css-uat` | `~/.ssh/css-uat.pem` | 个人公钥 `wenchao` |
| `css-non-prod-gw`（堡垒） | `css-non-prod-gw` | `~/.ssh/css-non-prod-gw.pem` | 个人公钥 `wenchao` |

个人钥 `~/.ssh/wenchao`（**带 passphrase**，口令见本地私有记录 `运维访问速查.local.md`）三台通用；专属 `.pem` 无 passphrase，脚本化更方便。
已实测：三把专属钥各自登录成功，且 **test 的私钥登不上 uat**（隔离有效）。

⚠️ 两条硬约束：
- **私钥只在创建那一刻由 AWS 返回一次**，之后再也取不到。本地 `.pem` 丢了只能 `aws ec2 delete-key-pair --key-name <名>` 后重跑脚本重建。
- **运行中实例的 `KeyName` 元数据改不了**（AWS 限制，属启动时属性），所以控制台上 `css-test-app` / `css-uat-app` 仍显示 `KeyName=wenchao`——**不影响登录**，决定谁能登录的是机器上的 `authorized_keys`，脚本写的正是它。要让元数据也一致只能重建实例（没必要）。

**登录**：

```bash
# --- 专属钥（推荐）---
ssh -i ~/.ssh/css-non-prod-gw.pem ec2-user@3.225.148.166                       # 堡垒机

ssh -i ~/.ssh/css-test.pem \
    -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' \
    ec2-user@10.20.10.10                                                       # test

ssh -i ~/.ssh/css-uat.pem \
    -o ProxyCommand='ssh -i ~/.ssh/css-non-prod-gw.pem -W %h:%p ec2-user@3.225.148.166' \
    ec2-user@10.20.11.10                                                       # uat

# --- 个人钥（三台通用，应急；带 passphrase）---
ssh -i ~/.ssh/wenchao -J ec2-user@3.225.148.166 ec2-user@10.20.10.10

# --- 免密钥走 SSM ---
aws ssm start-session --target i-0b3e73ed51811b69c
```
完整凭证/隧道/运维命令见工作区 `运维访问速查.local.md`（不入库）。

## 实例规格可以随时改

停机 → 改类型 → 开机，几分钟停机窗口；**私网 IP、实例角色、标签、ALB 目标注册都不变**：

```bash
aws ec2 stop-instances --region us-east-1 --instance-ids <id>
aws ec2 wait instance-stopped --region us-east-1 --instance-ids <id>
aws ec2 modify-instance-attribute --region us-east-1 --instance-id <id> --instance-type m7i-flex.xlarge
aws ec2 start-instances --region us-east-1 --instance-ids <id>
```
开机后 docker 由 systemd 自启，再跑一次 `09-ssm-run-command/deploy-env.sh <env>` 拉起容器即可。

## 可视化页面

**EC2 控制台**：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:>

- 看什么：① 实例列表状态与类型；② 选中实例 → **Security** 页签核对安全组与 IAM 角色；
  ③ **Networking** 页签确认私有 IP 与"无公有 IPv4"；④ **Tags** 页签确认 `CssEnv=css-<env>`（CI/CD 定位用）。
- **Session Manager**（免密钥上机）：<https://us-east-1.console.aws.amazon.com/systems-manager/session-manager>
- **Key pairs**（应有 4 条：`wenchao` + 三把专属 `css-test` / `css-uat` / `css-non-prod-gw`）：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#KeyPairs:>

## 注意

- 免费层实测可用的类型：`m7i-flex.large`、`c7i-flex.large`、`t3.micro/small`、`t4g.micro/small`；
  **`t3.large` 与 `t4g.nano` 不可用**（建机会被拒）。
- 新建实例默认引用 key pair `wenchao`；没导入过会给出提示并继续（此时只能经 SSM 登录）。**建机后请跑一次 `create-instance-keys.sh` 装该机专属钥**（`KeyName` 元数据仍会停留在建机时的值，正常，见上节）。
- 网关机做 NAT 必须关 source/dest check（脚本已处理）；它挂 `css-gw-non-prod` 角色（2026-07-29 由 `css-gw-nonprod`
  重建改名，同名 instance profile 一并重建并换绑，旧角色已删；实测 SSM 通道与读 dbsync 桶权限均正常），
  标签 **`CssEnv=css-shared`**（2026-07-29 起从"无标签"改为显式 `css-shared`，既满足"人人两标签"，
  又不会被 `deploy-env.sh` 误当成部署目标）。
- 网关机安全组 `css-non-prod-gw-sg`（`sg-0f449992d538ac3b4`）只剩 `22 ← 221.214.0.190/32` 与 `10.20.0.0/16 全协议`。**后者是 NAT 回程，不是 SSH，别删**——
  应用机没有公网 IP，出网全靠它转发，删了立刻断网（拉不了镜像、连不上 SSM）。
- 挂了新的实例 profile 后 SSM Agent 需要重启实例才会用上新凭证（网关机踩过这个坑）。
