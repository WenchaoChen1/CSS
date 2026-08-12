# 开发者 SSH 密钥发放台账

由 `grant-dev-ssh.sh` / `revoke-dev-ssh.sh` **自动追加**，**不含任何密钥材料**（私钥在 `deploy-env/ssh/dev-keys/`，gitignore）。
本文件是**发放历史**；**当前真正有效的条目以实时查询为准**：`./revoke-dev-ssh.sh --list [nonprod|prod]`
（直接读各机器 `authorized_keys`，含每条到期时间；过期条目由 OpenSSH 自动失效，无需人工清理）。

---

## 一、两套堡垒机 —— 发钥前先确认给的是哪一套

| 环境组 | 堡垒机 | 公网入口 | 这把钥匙能到达什么 |
|---|---|---|---|
| **nonprod**（非生产） | `css-non-prod-bastion`（`i-08b0ef319d08eae38`） | EIP `3.225.148.166` | test / uat 两个环境的应用机 + 共享 RDS |
| **prod**（生产） | `css-prod-bastion`（`i-0a6d6754c61c239d0`） | EIP `34.225.237.45` | 仅 prod 应用机（应用机与 RDS 尚未建，`enable_prod_compute` 门控中） |

⚠️ **两套完全隔离**：非生产的钥匙**到不了** prod（不同 VPC、不同堡垒机，`permitopen` 白名单也不含 prod 地址），反之亦然。
脚本已强制：`./grant-dev-ssh.sh 张三 30 prod test` 里的 `test` 会被**忽略并告警**——prod 的钥匙绝不会装到非生产应用机上。

## 二、两种权限档位 —— 由发钥时有没有 `apps` 参数决定

| 档位 | 命令 | 开发者实际能做什么 | 明确做不到什么 |
|---|---|---|---|
| **A. 纯隧道**（默认，不带 apps） | `./grant-dev-ssh.sh 张三 30` | ① 连数据库：把 RDS 5432 转发到本机（Navicat / DBeaver / psql）；② 访问内网 HTTP 服务（kafka-ui 等）；③ 经堡垒机跳到应用机 22 端口 | **不能在堡垒机上开 shell**（`no-pty`）、不能在堡垒机跑任何命令、不能转发到白名单以外的地址 |
| **B. 隧道 + 应用机 shell** | `./grant-dev-ssh.sh 张三 30 nonprod test` | A 的全部 + **登进 test 应用机开 shell**（看容器、查日志、跑 docker 命令） | 只覆盖参数里点名的环境；没点名的（如 uat）登不进去 |

**档位 A 的技术实现**（写进堡垒机 `authorized_keys` 的限制项）：

```
permitopen="10.20.10.10:22"        ← 只准转发到 test 应用机
permitopen="10.20.11.10:22"        ← 只准转发到 uat 应用机
permitopen="css-non-prod...:5432"  ← 只准转发到 RDS
expiry-time="YYYYMMDDHHMM"         ← 到期自动失效（不带 Z，按服务器本地时区解释；三台机器均为 UTC）
no-pty                             ← 不给伪终端 = 开不了 shell
no-agent-forwarding,no-X11-forwarding
```

prod 档位 A 的 `permitopen` 只有 `10.10.10.10:22`（prod 应用机），**不含 RDS**——生产库要连须另行评估授权。

## 三、发放 / 续期 / 撤销 / 查看

```bash
cd docs/环境运维执行脚本/06-服务器密钥与访问
./grant-dev-ssh.sh 张三 30                 # 非生产，30 天，纯隧道
./grant-dev-ssh.sh 张三 30 nonprod test    # + 可登 test 应用机
./grant-dev-ssh.sh 张三 14 prod            # 生产堡垒机（纯隧道，14 天）
./grant-dev-ssh.sh 张三 30                 # 【续期】同名重跑即可：复用同一把钥，只刷新到期时间
./revoke-dev-ssh.sh --list nonprod         # 查当前有效条目与到期时间
./revoke-dev-ssh.sh 张三 nonprod           # 立即撤销（不等到期），堡垒机 + 应用机一并清
```

产物：`deploy-env/ssh/dev-keys/<环境组>-<名字>.pem`（gitignore；**走安全渠道交付，勿发邮件/群聊**）。
开发者拿到后连库：`bash docs/环境运维执行脚本/05-数据库运维/db-tunnel.sh test`（用 `DEV_KEY=` 指向自己的钥）。

## 四、当前有效发放（2026-08-03 实时核对）

| 开发者 | 环境组 | 档位 | 到期（UTC） | 能做什么 |
|---|---|---|---|---|
| `dev1l` | nonprod | A 纯隧道 | 2026-09-02 06:47 | 连 test/uat 数据库、访问 kafka-ui；**不能开 shell、不能登应用机** |
| `dev2f` | nonprod | A 纯隧道 | 2026-09-02 02:41 | 同上 |

prod 堡垒机：**当前无任何开发者钥**。

> ⚠️ 2026-08-03 修复：此前 `expiry-time` 写成 ISO 格式（带 `T`/`Z`），OpenSSH 8.7 解析失败会**拒绝整条 key**——
> 在此之前发出去的钥匙其实从未生效过。现已改为纯 12 位 `YYYYMMDDHHMM`，并实测隧道打通。

## 五、记录（脚本自动追加，勿手工改格式）

- 2026-07-31 发放/续期 `dev1l`（nonprod）到期 **20260830T0808Z**，范围=堡垒机 ← ⚠️ 格式非法，该钥当时并未生效
- 2026-07-31 发放/续期 `dev2f`（nonprod）到期 **20260830T0809Z**，范围=堡垒机 ← ⚠️ 同上
- 2026-08-03 发放/续期 `dev1l`（nonprod）到期 **202609020232Z**，范围=堡垒机 ← ⚠️ 带 Z 仍非法（8.7 不支持 Z 后缀）
- 2026-08-03 发放/续期 `dev2f`（nonprod）到期 **202609020232Z**，范围=堡垒机 ← ⚠️ 同上
- 2026-08-03 发放/续期 `dev1l`（nonprod）到期 **202609020241**，范围=堡垒机 ✅ 生效（实测隧道通）
- 2026-08-03 发放/续期 `dev2f`（nonprod）到期 **202609020241**，范围=堡垒机 ✅ 生效
- 2026-08-03 `dev1l` @ nonprod 堡垒机（css-non-prod-bastion 3.225.148.166，通 test/uat 应用机与共享 RDS）｜到期 **202609020647** UTC｜档位A：纯隧道（连库/内网HTTP/跳板，堡垒机上开不了 shell）
- 2026-08-12 `dev1l` @ prod 堡垒机（css-prod-bastion 34.225.237.45，仅通 prod 应用机）｜到期 **202609110856** UTC｜档位A：纯隧道（连库/内网HTTP/跳板，堡垒机上开不了 shell）
- 2026-08-12 `dev2f` @ prod 堡垒机（css-prod-bastion 34.225.237.45，仅通 prod 应用机）｜到期 **202609110856** UTC｜档位A：纯隧道（连库/内网HTTP/跳板，堡垒机上开不了 shell）
