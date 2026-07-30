# 12-alb —— 系统入口 ALB（Web 只经 ALB 访问）

**访问规范（2026-07-28 拍板，2026-07-29 收口完成）**：

1. 所有 EC2 的 **SSH/IP 直连一律只经堡垒机**（nonprod=`css-non-prod-gw` EIP 3.225.148.166、prod=`css-prod-bastion`，仅放行管理 IP 221.214.0.190/32）；
2. **系统（Web）只能通过 ALB 访问**，应用机全部在私有子网、无公网 IP；
3. **RDS 只能内网访问**（`--no-publicly-accessible`，安全组仅放行 app / 堡垒安全组的 5432）。

## 命名：每环境一个 ALB，名字就是环境名（2026-07-29 拍板）

| 环境 | ALB 名 | 目标组 | 目标 |
|------|--------|--------|------|
| test | `css-test` | `css-test-fe-tg` | 10.20.10.10:80 |
| uat | `css-uat` | `css-uat-fe-tg` | 10.20.11.10:80 |
| prod | `css-prod` | `css-prod-fe-tg` | 10.10.10.10:80 |

- 旧的**共享** ALB `css-nonprod-alb` 已删除；随之作废的还有**"uat 按 Host 头分流"**——那是共享 ALB 时代的方案，
  现在每环境独立 ALB，各有独立 DNS，不配域名也能各访问各的。
- ALB 与目标组都打**双标签**：`Group=css-non-prod|css-prod` + `CssEnv=css-<env>`。
- 第二个参数 `[域名]` 现在的作用只是（配了 `CERT_ARN` 时）给 HTTPS 用的主机名，不再用于分流。

| 脚本 | 作用 |
|------|------|
| `create-alb.sh <test\|uat\|prod> [域名]` | 建/更新**该环境**的 ALB：安全组、目标组、监听器、WebSocket idle timeout、双标签 |
| `revoke-gw-proxy.sh <nonprod\|prod>` | **收掉网关机的 Web 过渡通道**（ALB 接管后执行，见下） |
| `revoke-kafkaui-public.sh <test\|uat\|prod>` | 回收**该环境** kafka-ui 的公网暴露（监听器+目标组+安全组规则）。参数由原 `<nonprod\|prod>` 改为环境名——ALB 已改成每环境一个，旧的共享 `css-nonprod-alb` 已不存在 |

## 转发设计

| 入口 | 去向 | 说明 |
|------|------|------|
| `:80`（`:443` 给了 `CERT_ARN` 时） | 本环境应用机 `:80`（前端容器） | 前端 nginx 把 `/api` `/ws` `/notifications` **同源反代**到后端 nginx，浏览器只看到一个源，无 CORS |
| WebSocket | 同上（ALB 原生支持 Upgrade） | 脚本把 `idle_timeout` 提到 **3600s**，与前端 nginx 的 `proxy_read_timeout 3600s` 对齐，避免长连接被默认 60s 掐断 |

**kafka-ui（:8085）默认不挂 ALB** —— 它无认证且能读到 `sms_send` 里的 2FA 验证码；而本机 HTTP 出口是**会漂移的代理 IP**
（实测 103.62.49.138 / 134.195.101.194 轮换），IP 白名单既不安全也不可靠（实测挂上去后自己都访问不了，返回代理的 502）。
正确访问方式是堡垒机隧道：

```bash
ssh -i ~/.ssh/css-non-prod-gw.pem -N -L 8085:10.20.10.10:8085 ec2-user@3.225.148.166
# 浏览器打开 http://localhost:8085 → Topics → sms_send
```

确有公网需求时显式指定固定出口 IP：`KAFKA_UI_CIDR=1.2.3.4/32 ./create-alb.sh test`。

## 怎么用

```bash
cd docs/新aws账号/12-alb
./create-alb.sh test                         # 已执行 ✅
./create-alb.sh uat                          # 已执行 ✅
CERT_ARN=arn:aws:acm:us-east-1:...:certificate/xxx ./create-alb.sh test test.你的域名.com   # 补 443
./create-alb.sh prod                         # ⏳ 等 prod 应用机建好
```

- 💰 计费：**每个 ALB** ~$16/月 + LCU（估算 ~$20/月）；现在是 2 个 → ~$40/月，另加各 2 个节点公网 IPv4。
- HTTPS：先在 ACM 申请证书（DNS 验证，免费），拿到 ARN 后用 `CERT_ARN` 重跑即可补 443 监听器。
- 幂等：已存在的 ALB/目标组/监听器会复用，目标重新注册。

## 当前实况（2026-07-29）

| 项 | `css-test` | `css-uat` | `css-prod` |
|----|-----------|-----------|-----------|
| 状态 | ✅ Active | ✅ Active | ⏳ 未创建（等 prod 应用机） |
| DNS | `css-test-524317374.us-east-1.elb.amazonaws.com` | `css-uat-1366981991.us-east-1.elb.amazonaws.com` | — |
| 监听器 | `:80` → `css-test-fe-tg` | `:80` → `css-uat-fe-tg` | — |
| 目标 | 10.20.10.10:80 **healthy** | 10.20.11.10:80 **unhealthy**（uat 未部署，属正常） | — |
| 标签 | `Group=css-non-prod` + `CssEnv=css-test` | `Group=css-non-prod` + `CssEnv=css-uat` | 将为 `Group=css-prod` + `CssEnv=css-prod` |
| 实测 | 前端 `/` → **200** ✅ | 未部署，503 | — |

- 安全组：`css-non-prod-alb-sg` = `sg-0c7b0b571d74b1f2f`（80/443 公网），两个非生产 ALB 共用；app-sg 的 80 只收它。
  （2026-07-29 由 `css-nonprod-alb-sg`/`sg-0c8f420e1e46b5b4b` 新建迁移而来，过程见 [01-vpc](../01-vpc/README.md) 的"安全组改名"一节。）
- 待办：绑域名 → ACM 证书 → 443；uat 部署后目标转 healthy；prod 应用机就绪后建 `css-prod`。

## 网关机过渡通道已收口（`revoke-gw-proxy.sh`，2026-07-29 已执行）

ALB 接管 Web 之后，网关机上那套临时反代必须撤掉。脚本做三件事（幂等）：

1. 撤销 `gw-sg` 上给管理 IP 开的 **80 / 8080**（原来用来反代 test/uat 前端的临时口子）；
2. 撤销 `app-sg` 上**"来自 gw-sg 的 80"**（应用机的 Web 端口此后只收 ALB）；
3. 经 SSM 在网关机上 **停用并禁用 nginx**（不需要 SSH）。

```bash
./revoke-gw-proxy.sh nonprod    # 已执行 ✅
./revoke-gw-proxy.sh prod       # prod 堡垒机若装过反代再跑
```

收完后的目标状态：

| 安全组 | 入站规则 | 用途 |
|--------|----------|------|
| `css-non-prod-gw-sg`（`sg-0f449992d538ac3b4`） | `22 ← 221.214.0.190/32` | SSH 跳板（唯一管理入口） |
| `css-non-prod-gw-sg` | `10.20.0.0/16` **全协议** | **NAT 回程** |
| `css-non-prod-app-sg`（`sg-0d06e029924989ee3`） | `22 ← gw-sg` | SSH 只收堡垒机 |
| `css-non-prod-app-sg` | `80 ← alb-sg` | Web 只收 ALB |

> ⚠️ **`10.20.0.0/16 全协议`那条不是给 SSH 的，别删**：私有子网的 test/uat 没有公网 IP，出网全靠网关机做 NAT 转发，
> **回程流量必须放行**。删了它两台机器立刻断网——拉不了 ECR 镜像、连不上 SSM，部署与远程运维全部失效。

`01-vpc/create-vpc.sh` 已同步：不再放行 gw-sg 的 80/8080；`06-ec2/create-gateway.sh` 也不再安装 nginx 反代。

## 可视化页面

**EC2 控制台 → Load Balancers**：<https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#LoadBalancers:>

- 看什么：① 列表里应有 `css-test`、`css-uat` 两个，状态 **Active**；② **Listeners and rules** 页签核对 80（有证书时 443）；
  ③ **Attributes** 里 idle timeout=3600；④ Target groups → `css-<env>-fe-tg` → **Targets** 页签健康状态
  （容器没起来时是 unhealthy，此时 ALB 返回 503——uat 现在就是这个状态）；⑤ **Tags** 页签核对 `Group` + `CssEnv` 双标签。

## 注意

- 目标组按**固定私网 IP** 注册（`target-type ip`），换机器只要 IP 不变就无需改 ALB；实例改规格也不影响。
- 前端 `VITE_API_BASE_URL` / `VITE_WS_BASE_URL` 是**构建期烤进镜像**的：改成 ALB DNS 或域名后必须**重新构建前端镜像**，重启容器无效。
- ALB 停不了机：uat 应用机 stop 省钱时，`css-uat` ALB 的固定费仍照收。
