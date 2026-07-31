# 06-服务器密钥与访问 —— SSH 密钥（一机一钥 / 开发者临时钥）与终止保护开关（原 06-ec2）

> ⚠️ **2026-07-30 起本目录创建类脚本已删除**（本 README 保留作资源说明/运维参考）：机器创建/删除已由 css-terraform 接管（network 的网关机 + 各环境 ec2 stack）：create-app-ec2.sh/create-gateway.sh/delete-ec2.sh 废弃删除；本目录现存 5 个脚本（密钥/访问/终止保护，不进 TF）。
> 资源变更一律走 css-terraform 仓库（规范见其 CLAUDE.md）。

**访问铁律**：应用机全在私有子网、无公网 IP，SSH 只能经堡垒机跳，Web 只能经本环境 ALB（kafka-ui 只走开发入口 ALB `css-non-prod-entry`）。

## 脚本清单

```bash
cd docs/新aws账号/06-服务器密钥与访问
```

### `setup-ssh-key.sh` — 把本机 SSH 公钥装进 AWS：导入为 EC2 key pair，并可选经 SSM 补装到已存在实例的 `authorized_keys`

```bash
./setup-ssh-key.sh [公钥文件] [实例名或ID ...]        # 公钥缺省 ~/.ssh/wenchao.pub；key pair 名=文件名去 .pub
./setup-ssh-key.sh ~/.ssh/wenchao.pub                 # 只导入 key pair（新建实例用 --key-name 引用）
./setup-ssh-key.sh ~/.ssh/wenchao.pub css-non-prod-gw # 导入 + 装到网关机（已建实例无法事后绑 key pair，只能这样补）
```

幂等：指纹一致则跳过；补装实例需已注册 SSM（未注册会跳过）。

### `create-instance-keys.sh` — 一机一钥：为每台机器创建专属 ed25519 key pair（私钥落本机 `~/.ssh/<名>.pem`），经 SSM 把「专属公钥 + 个人公钥」写进 `authorized_keys`（幂等去重）

```bash
./create-instance-keys.sh [个人公钥文件] [只处理某台: css-test|css-uat|css-non-prod-gw]
./create-instance-keys.sh                             # 三台全做，个人公钥默认 ~/.ssh/wenchao.pub
./create-instance-keys.sh ~/.ssh/wenchao.pub css-uat  # 只补 uat 一台
```

注意：AWS 私钥只在创建那一刻返回一次，本地 `.pem` 丢了只能删 key pair 重跑重建（详见下文"SSH 密钥"节）。

### `grant-dev-ssh.sh` — 给开发人员发放带过期时间的 SSH 密钥（堡垒机必装；可选同时装到应用机）

```bash
./grant-dev-ssh.sh <开发者名> <有效天数> [nonprod|prod] [apps...]   # apps 可选 test/uat：同一把钥匙也装到应用机（同样带过期）
./grant-dev-ssh.sh zhangsan 30                        # 非生产堡垒机，30 天，仅隧道（够用 RDS/kafka-ui 场景，登不进应用机）
./grant-dev-ssh.sh zhangsan 30 nonprod test           # + 可登 test 应用机
./grant-dev-ssh.sh zhangsan 14 prod                   # 生产堡垒机
```

原理：`authorized_keys` 的 `expiry-time` 选项到期自动失效，无需人工清理；堡垒机条目额外加 `no-pty` + `permitopen`（纯跳板，不能开 shell、只能转发到白名单目标）。
产物：`./dev-keys/<环境>-<开发者名>.pem`（已 gitignore；安全渠道交付）。
**续期**：同名重跑本脚本即可（复用同一把钥，只把到期时间刷新为 今天+`<天数>`），开发者手里的私钥不用换；改权限范围（如补 apps）同样是同名重跑。
**台账**：每次发放/续期/撤销自动追加到 [`dev-ssh发放记录.md`](dev-ssh发放记录.md)（谁、哪个环境、什么范围、何时到期；不含密钥材料）；**当前实际有效**的条目用 `./revoke-dev-ssh.sh --list` 实时查（直接读机器上的 authorized_keys）。

### `revoke-dev-ssh.sh` — 撤销/查看开发者 SSH 条目（堡垒机 + test/uat 应用机一并处理，配合 grant-dev-ssh.sh）

```bash
./revoke-dev-ssh.sh --list [nonprod|prod]             # 列出各机器的开发者条目及到期时间
./revoke-dev-ssh.sh <开发者名> [nonprod|prod]          # 立即撤销（不等到期）；本地 ./dev-keys/*.pem 可一并删除
```

### `toggle-termination-protection.sh` — 开/关 EC2 终止保护（`disable_api_termination`）

```bash
./toggle-termination-protection.sh <实例ID|Name标签> <on|off>
./toggle-termination-protection.sh css-test-app off   # Terraform 重建实例（replace）前必须先关——TF destroy 不会自动解除，直接 apply 会报错
```

注意：重建出的新实例由 Terraform 自动带保护，无需再手动开。

## 当前实况（2026-07-31；机器由 css-terraform 管理）

| 名称 | 实例 ID | 规格 | 地址 | 标签 `Environment` | 状态 |
|------|---------|------|------|---------------|------|
| `css-non-prod-bastion`（原名 css-non-prod-gw） | i-08b0ef319d08eae38 | t4g.micro | EIP **3.225.148.166** / 10.20.0.74 | `css-shared` | ✅ **只剩堡垒(22) + NAT**（nginx 过渡反代 07-29 已收） |
| `css-test-app` | i-0cb9b69b9eb19a9aa | m7i-flex.large | 10.20.10.10（无公网） | `css-test` | ✅ 三栈已部署，入口 ALB `css-test`（07-30 重建，KeyName=css-test，根卷加密） |
| `css-uat-app` | i-0f90c5c061d640a27 | m7i-flex.large | 10.20.11.10（无公网） | `css-uat` | ✅ 已建机，**未部署**；ALB `css-uat` 已建（07-30 重建，KeyName=css-uat） |
| `css-prod-bastion` | i-0a6d6754c61c239d0 | t4g.micro | EIP **34.225.237.45** | `css-shared` | ✅ 已建在跑（密钥 `~/.ssh/css-prod-bastion`） |
| `css-prod-app` | — | — | 规划 10.10.10.10 | `css-prod` | ⏳ `enable_prod_compute` 门控，等 Paid plan |

> 堡垒机的 `Environment` **必须是 `css-shared`**：`ssm:SendCommand` 的 IAM 条件与 `run.sh`/`deploy-env.sh`
> 按 `Environment=css-<env>` 定位部署目标机，打成 `css-test` 会让堡垒机被 test 的部署命令选中。

## SSH 密钥（一机一钥，2026-07-29）

**凭证不跨机复用**：每台机器一把**专属** EC2 key pair（ed25519，无 passphrase），私钥只在本机；
同时每台的 `authorized_keys` 里**额外**保留个人公钥 `wenchao` 作为通用/应急第二通道。由 `create-instance-keys.sh` 一键建齐。

| 机器 | 专属 key pair | 本机私钥 | 第二通道 |
|------|---------------|----------|----------|
| `css-test-app` | `css-test`（=实例 KeyName） | `~/.ssh/css-test.pem` | —（07-30 重建后 authorized_keys 只有专属钥） |
| `css-uat-app` | `css-uat`（=实例 KeyName） | `~/.ssh/css-uat.pem` | — |
| `css-non-prod-bastion`（堡垒） | `css-non-prod-gw`（沿用旧名） | `~/.ssh/css-non-prod-gw.pem` | 个人公钥 `wenchao` |
| `css-prod-bastion` | `css-prod-bastion` | `~/.ssh/css-prod-bastion` | — |

个人钥 `~/.ssh/wenchao`（**带 passphrase**，口令见本地私有记录 `运维访问速查.local.md`）现仅在非生产堡垒机上作应急第二通道；专属 `.pem` 无 passphrase，脚本化更方便。
已实测：专属钥各自登录成功，且 **test 的私钥登不上 uat**（隔离有效）。

⚠️ 两条硬约束：
- **私钥只在创建那一刻由 AWS 返回一次**，之后再也取不到。本地 `.pem` 丢了只能 `aws ec2 delete-key-pair --key-name <名>` 后重建 key pair 并重装公钥。
- **运行中实例的 `KeyName` 元数据改不了**（AWS 限制，属启动时属性）。test/uat 应用机曾因此显示 `KeyName=wenchao`，**2026-07-30 已重建修正**（现 KeyName=css-test/css-uat，与专属钥一致）；真正决定谁能登录的始终是机器上的 `authorized_keys`。

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

# --- 免密钥走 SSM ---
aws ssm start-session --target i-0cb9b69b9eb19a9aa    # test；uat=i-0f90c5c061d640a27，堡垒=i-08b0ef319d08eae38
```
完整凭证/隧道/运维命令见工作区 `运维访问速查.local.md`（不入库）。

## 实例规格可以随时改（⚠️ 走 Terraform，不要裸命令）

实例已由 css-terraform 纳管——**改规格 = 改 `css-terraform/<组>/<env>/ec2` 的 `instance_type` 变量后 `terraform apply`**
（TF 自动做停机→改型→开机，几分钟窗口；私网 IP、角色、标签、ALB 目标注册都不变）。
裸 `aws ec2 modify-instance-attribute` 改类型会造成 drift，下次 plan 会要求改回去。
开机后 docker 由 systemd 自启，再跑一次 `09-远程执行与手动部署/deploy-env.sh <env>` 拉起容器即可。

## 可视化页面

**EC2 控制台**：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#Instances:>

- 看什么：① 实例列表状态与类型；② 选中实例 → **Security** 页签核对安全组与 IAM 角色；
  ③ **Networking** 页签确认私有 IP 与"无公有 IPv4"；④ **Tags** 页签确认 `Environment=css-<env>`（CI/CD 定位用）。
- **Session Manager**（免密钥上机）：<https://us-east-1.console.aws.amazon.com/systems-manager/session-manager>
- **Key pairs**（应有 5 条：`wenchao` + 专属 `css-test` / `css-uat` / `css-non-prod-gw` / `css-prod-bastion`）：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#KeyPairs:>

## 注意

- 免费层实测可用的类型：`m7i-flex.large`、`c7i-flex.large`、`t3.micro/small`、`t4g.micro/small`；
  **`t3.large` 与 `t4g.nano` 不可用**（建机会被拒）。
- 建机/重建走 css-terraform `ec2` stack，`key_name` 已配专属钥（要求 key pair 先存在——新环境先跑 `create-instance-keys.sh` 或手动建）；建成后如需给机器补装其他公钥用 `setup-ssh-key.sh`。
- 堡垒机做 NAT 必须关 source/dest check（Terraform 已配 `source_dest_check=false`）；它挂 `css-gw-non-prod` 角色，
  标签 **`Environment=css-shared`**（既满足"人人两标签"，又不会被 `deploy-env.sh` 误当成部署目标）。
- 堡垒机安全组 `css-non-prod-bastion-sg`（`sg-0b0a1508e6063d23f`，原 css-non-prod-gw-sg 已删）只剩 `22 ← 管理 IP` 与 `10.20.0.0/16 全协议`。**后者是 NAT 回程，不是 SSH，别删**——
  应用机没有公网 IP，出网全靠它转发，删了立刻断网（拉不了镜像、连不上 SSM）。
- 挂了新的实例 profile 后 SSM Agent 需要重启实例才会用上新凭证（堡垒机踩过这个坑）。
