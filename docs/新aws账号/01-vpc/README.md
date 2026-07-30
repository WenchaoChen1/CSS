# 01-vpc —— 网络骨架（VPC / 子网 / IGW / 路由 / S3 端点 / 安全组）

> ⚠️ **2026-07-30 起本目录创建类脚本已废弃**：非生产网络/SG 已由 css-terraform 接管（css-non-prod/network + 各环境 sg stack）：create-vpc.sh 勿再执行；旧共用 css-non-prod-app-sg/alb-sg 已退役删除，现为每环境独立 css-<env>-app-sg/alb-sg。
> 资源变更一律走 css-terraform 仓库（规范见其 CLAUDE.md）。

一条命令建出一组环境的全套零成本网络：VPC + 2 公有 2 私有子网（跨 1a/1b 两 AZ）+ IGW + 公私路由表 + S3 Gateway 端点 + 安全组，全部打 `Group` 标签，幂等可重复执行。

## 怎么用

```bash
cd docs/新aws账号/01-vpc
./create-vpc.sh nonprod   # css-non-prod：10.20.0.0/16（test+uat 共用）
./create-vpc.sh prod      # css-prod：   10.10.0.0/16
```

- 幂等：按 Name 标签查找已有资源，存在即复用，重复跑安全。
- 网段约定：公有 `x.x.0/1.0/24`，私有 `x.x.10/11.0/24`；管理白名单 IP 写死在脚本 `ADMIN_CIDR`。
- 拓扑设计见 `docs/环境/aws-css-non-prod.md` 与 `aws-css-prod.md`。

## 标签（2026-07-29）

本目录建的全部是**跨环境共享**的网络骨架，所以统一打：

- `Group` = `css-non-prod` | `css-prod`
- `CssEnv` = **`css-shared`**（脚本里的 `SHARED_ENV`）

> ⚠️ **绝对不能给这些资源打 `css-test`/`css-uat`**：IAM 的 `ssm:SendCommand` 条件和 `09-ssm-run-command/run.sh`、
> `deploy-env.sh` 都按 `CssEnv=css-<env>` **定位部署目标机**。VPC/子网/安全组/网关机一旦带上 `css-test`，
> 就可能被 test 的部署命令选中，往错误的对象上发部署。

## 安全组现状（2026-07-29 收口后）

非生产组（`css-non-prod`，**2026-07-29 已统一改名为 `css-non-prod-*`**，见下一节）：

| SG | ID | 入站 | 说明 |
|----|----|------|------|
| `css-non-prod-gw-sg` | `sg-0f449992d538ac3b4` | `22 ← 221.214.0.190/32` | SSH 跳板，唯一管理入口 |
| `css-non-prod-gw-sg` | 同上 | `10.20.0.0/16` **全协议** | **NAT 回程**（见下方警告） |
| `css-non-prod-alb-sg` | `sg-0c7b0b571d74b1f2f` | `80 / 443 ← 0.0.0.0/0` | 两个非生产 ALB（`css-test` / `css-uat`）共用 |
| `css-non-prod-app-sg` | `sg-0d06e029924989ee3` | `22 ← gw-sg`；`80 ← alb-sg` | 应用机就这两条，没有别的 |
| `css-non-prod-rds-sg` | `sg-0197c0db4578107ef` | `5432 ← app-sg`、`5432 ← gw-sg` | 仅内网 |

生产组（`css-prod`）同构，把 `gw-sg` 换成 `css-prod-bastion-sg`；生产那 4 个（`css-prod-alb-sg` / `css-prod-app-sg` /
`css-prod-bastion-sg` / `css-prod-rds-sg`）本来就合规，**未参与改名，ID 不变**。

> ⚠️ **`10.20.0.0/16 全协议`那条不是给 SSH 的，别删**：私有子网的 test/uat 应用机**没有公网 IP**，
> 出网全靠网关机做 iptables NAT 转发，**回程流量必须放行**。删了它两台机器立刻断网——
> 拉不了 ECR 镜像、连不上 SSM，部署和远程运维全废。

**已收掉的过渡通道**：2026-07-29 起 Web 一律走 ALB，`gw-sg` 的 **80 / 8080** 入站和 `app-sg` 的**"来自 gw-sg 的 80"**
已被 `12-alb/revoke-gw-proxy.sh` 撤销，网关机 nginx 已停用并禁用；本脚本也**不再放行**这两个端口
（重跑 `create-vpc.sh` 不会把它们加回来）。

## 安全组改名 `css-nonprod-*` → `css-non-prod-*`（`rename-security-groups.sh`，2026-07-29 已完成）

### 为什么要"新建 + 迁移"而不是直接改名

**AWS 安全组的 `GroupName` 与 `Description` 创建后都不可修改**（只有 `Name` 标签能随便改，但标签不是组名）。
要让组名与 VPC / RDS / `Group` 标签一样带连字符，只能：**建新的同规则 SG → 把引用它的资源切过去 → 删旧的**。
脚本用「双挂」把这件事做成零中断：安全组之间是**取并集**的，资源同时挂新旧两个时业务照常走旧规则，
任何一步不对都可以停下来。旧 4 个 SG 已删除，新 ID 见上表；实例 ID、EIP、ALB、RDS 端点均未变。

### 六个动作怎么用

```bash
cd docs/新aws账号/01-vpc
./rename-security-groups.sh plan      # 只打印将做什么，不改任何东西
./rename-security-groups.sh apply     # 建 4 个新 SG + 灌规则（交叉引用指向新 SG）+ 给 gw/test/uat/两个 ALB/RDS 双挂
./rename-security-groups.sh verify    # 5 项连通性检查（ALB 200 / 目标组 healthy / SSM / NAT 出网 / 应用连 RDS）
./rename-security-groups.sh canary    # 金丝雀：只把 uat 机切成【仅新 SG】，再 ./rename-security-groups.sh verify-uat
./rename-security-groups.sh cutover   # 真正的切换点：所有资源摘掉旧 SG，只留新的（切换前自动做等价性门禁）
./rename-security-groups.sh verify    # 切换后复验，5 项应与切换前完全一致
./rename-security-groups.sh cleanup   # 删除已零引用的旧 SG，并打印最终 SG 清单
```

**回退**：`cutover` 后若 `verify` 失败，立刻重跑 `apply`——它会把旧 SG 挂回去，一条命令恢复。

### 迁移过程中踩到/防住的四件事

1. **双挂状态下的连通性验证是假阳性发生器**：新旧规则取并集，旧 SG 独力就能让 5 项全绿，证明不了新 SG 有任何一条规则是对的。
   真正的把关是两道：① `cutover`/`canary` 前自动跑**新旧规则集逐条 diff**（把交叉引用的 SG ID 归一化成 `@GW/@ALB/@APP/@RDS` 再比），
   不等价直接拒绝执行；② 拿 **uat 做金丝雀**先切一台、只在新 SG 下验 SSM + NAT + ICMP，通过了才切 test 和网关机。
2. **删旧 SG 必须按依赖倒序 `rds → app → alb → gw`**：旧 app-sg 的规则引用旧 gw/alb-sg，旧 rds-sg 引用旧 gw/app-sg，
   先删 gw 会 `DependencyViolation`——哪怕已经没有任何网卡挂着它，只要还被别的 SG 的规则引用就删不掉。
3. **NAT 回程必须是全协议 `-1`**，脚本单独断言了这条：退化成 tcp 会丢 ICMP → PMTUD 黑洞（大响应体挂死，极难排查）。
4. **安全组是 stateful（有状态）的**：移除规则时 AWS 不保证保留已建立的连接，长连接（RDS 连接池、SSM 通道、WebSocket）
   可能被重置并自动重连，属预期内抖动，不是故障。

> 顺带清掉了旧默认 VPC 里两个零引用的死安全组：`css-non-prod-db-sg`(`sg-095c23f15e3ed642b`)、
> `css-non-prod-ec2-sg`(`sg-08e01c425f5f35359`)。

## 默认 VPC 已删除（`delete-default-vpc.sh`，✅ 2026-07-29）

账号自带的默认 VPC **`vpc-0f1a28d652c598172` 及其 6 个子网、IGW、路由表、默认安全组、RDS `default` 子网组已全部删除**。
现在 us-east-1 里**只有两个自建 VPC**：`css-non-prod`(10.20.0.0/16) 与 `css-prod`(10.10.0.0/16)。

为什么删：① 默认 VPC 与它的 6 个子网**打不了有意义的标签**（不属于任何环境），永远是标签合规检查里的例外；
② 控制台/CLI 不显式指定 VPC 时会默认落到它里面，**容易误建资源**（旧 test 机与旧 RDS 就是这么来的，均已删）。

```bash
./delete-default-vpc.sh us-east-1        # 只做空置校验，不删
./delete-default-vpc.sh us-east-1 yes    # 校验通过后真正删除
```

脚本删前逐项断言默认 VPC 完全空置（EC2 实例 / 网络接口 / NAT / VPC 端点 / 非 default 的 RDS 子网组 /
非默认安全组 / 对等连接），任何一项非空直接拒绝。**可逆**：需要时
`aws ec2 create-default-vpc --region us-east-1` 一条命令即可重建（新 VPC 是新 ID，里面本来就没东西）。

## 可视化页面

**VPC 控制台**（新账号 582797602427 / us-east-1）：

- 直达：<https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#vpcs:>
- 入口路径：控制台 → VPC → Your VPCs

在页面上看什么：

1. VPC 列表**总共只应有两个** VPC（默认 VPC 已删，见上节）：按标签 `Group=css-non-prod` / `Group=css-prod` 过滤，确认 CIDR 为 10.20.0.0/16 / 10.10.0.0/16。
2. 左侧切到 **Subnets**：每组应有 4 个子网（`*-public-1a/1b`、`*-private-1a/1b`），AZ 与 CIDR 对得上。
3. **Route tables**：公有路由表默认路由指向 IGW；私有路由表暂无出网路由（等 06-ec2 网关建好后补）。
4. **Endpoints**：每个 VPC 有一个 S3 Gateway 端点；**Security groups** 里能看到各组的 app/rds/gw 安全组。

## 状态/注意

- ✅ 2026-07-28 两组均已执行：`css-non-prod=vpc-014be109b904d6a07`、`css-prod=vpc-0ecf70f71565ddcc8`。
- ✅ 2026-07-29 **默认 VPC `vpc-0f1a28d652c598172` 已删除**（`delete-default-vpc.sh`），账号里只剩上面两个自建 VPC。
- 全部资源零成本，可随时重跑核对。
- 后续脚本（04-rds / 06-ec2）都按 Name 标签查这里建的子网/安全组，删改标签会导致它们找不到资源。
