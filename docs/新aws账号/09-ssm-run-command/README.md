# 09-ssm-run-command —— SSM 命令通道 + EC2 端 deploy.sh 完整手册

SSM Run Command 是 CI/CD 从 GitHub 通向（私网）EC2 的命令通道：**不开 22 端口、不用 pem、无需任何入站规则**（EC2 上的 SSM Agent 主动向 AWS 出站长连接）。本文覆盖：脚本用法、机器前置配置、可视化页面、以及 SSM 送达后在机器上执行的 **deploy.sh 全手册**。具体值见 [../../环境/配置速查.md](../../环境/配置速查.md)。

## 一、本文件夹的脚本

```bash
# ① 把一台 EC2 配置成 SSM 部署目标（挂角色/补权限 + 打 CssEnv=css-<env> 标签 + 等 Online）
bash docs/新aws账号/09-ssm-run-command/setup-ssm.sh test i-08e110b5a5425980d

# ② 对某环境远程执行任意命令（按 CssEnv 标签定位，JSON 安全编码，回显输出）
bash docs/新aws账号/09-ssm-run-command/run.sh test 'docker ps --format "{{.Names}} {{.Status}}"'
```

- `setup-ssm.sh` 幂等：机器没角色→挂 `css-ec2-<env>`；已有别的角色→不替换、补挂 SSM 策略和本环境参数读取（现有 test 机即此情况，已配好）；
- `run.sh` 与 CI 用的 `deploy/aws/ssm-run.sh` 同源（最长等 20 分钟、失败退出非 0）；
- 用 `06-ec2` 新建的机器无需 setup（脚本已含角色与标签）。

## 二、工作原理与机器前置

```
workflow（已持 css-deploy-<env> 临时凭证）
  └─ run.sh <env> '<命令>'
       ① describe-instance-information：找 标签 CssEnv=css-<env> 且 Ping=Online 的实例
       ② send-command（文档 AWS-RunShellScript，root 身份执行）
       ③ 每 5s 轮询直到终态 → 回显 stdout/stderr，失败退出非 0 → workflow 红
```

权限收口在 IAM：`css-deploy-<env>` 的 `ssm:SendCommand` 带条件 `ssm:resourceTag/CssEnv=css-<env>`——**test 的流水线在 IAM 层面就发不到 uat/prod 的机器**。

**每台应用机的前置（两处，新机一次性；控制台路径）**：
1. **实例角色**：EC2 → Instances → 勾选实例 → **Actions → Security → Modify IAM role** → 选 `css-ec2-<env>`（角色含 SSM 托管策略 + ECR 只读 + 读本环境参数）；
2. **标签**：实例页 **Tags** 页签 → `Key=CssEnv, Value=css-test|css-uat|css-prod` + `Key=Group, Value=css-non-prod|css-prod`（值必须带 `css-` 前缀，setup-ssm.sh 会自动打）。
3. 机器必须能**出站**（私网机器经网关机 NAT / NAT 网关）；角色刚变更后 Agent 刷新凭证可能要几分钟。

验证就绪：

```bash
aws ssm describe-instance-information --filters "Key=tag:CssEnv,Values=css-test" --query "InstanceInformationList[].{id:InstanceId,ping:PingStatus}" --output table
```

## 三、可视化页面

| 看什么 | 在哪 |
|--------|------|
| **命令执行历史**（每次 CI 部署都有记录，含 deploy.sh 完整输出） | Systems Manager → **Run Command** → Command history：`https://us-east-1.console.aws.amazon.com/systems-manager/run-command/complete-commands?region=us-east-1`，点 Command ID → 选实例 → Output |
| 哪些机器 SSM 在线 | **Fleet Manager**：`https://us-east-1.console.aws.amazon.com/systems-manager/fleet-manager/managed-nodes?region=us-east-1`（Ping status 应为 Online） |
| 网页版终端上机（代替 SSH） | **Session Manager** → Start session：`https://us-east-1.console.aws.amazon.com/systems-manager/session-manager?region=us-east-1`；命令行 `aws ssm start-session --target <实例id>` |
| 机器的角色/标签 | EC2 实例页 → Security 页签（IAM Role）、Tags 页签（CssEnv/Group） |

与堡垒机的关系：CI/CD 部署**不经过堡垒机**；堡垒机（非生产网关机）是给人用的（SSH 跳板、psql 隧道、浏览器访问 test/uat 页面）。SSM 与堡垒机互为备份通道。

## 四、SSM 送达后：EC2 端 deploy.sh 手册

### 脚本在哪

| 位置 | 说明 |
|------|------|
| 源码 | Backend 仓库 `deploy/bin/deploy.sh`（改它=改部署行为，走分支流程经 test 验证） |
| EC2 上 | `/opt/css-cicd/bin/deploy.sh` —— **每次 CI 部署自动上传刷新**，永远与仓库同版本 |

### 配置从哪来（你只需维护 Parameter Store 一处）

deploy.sh 每次部署前自动把 `/css/<env>/backend.env` 渲染成机器上的 env 文件。参数页面：Systems Manager → **Parameter Store**：`https://us-east-1.console.aws.amazon.com/systems-manager/parameters?region=us-east-1`

| 参数名 | 内容 | 类型 |
|--------|------|------|
| `/css/<env>/backend.env` | 后端运行时全量 env（≈88 变量，整份文件一个值） | SecureString，**Advanced 层** |
| `/css/<env>/frontend.env` | 5 个 `VITE_*` 构建期变量 | SecureString，Standard |

改参数：点参数 → **Edit** → 改 Value → 保存 → **重跑对应环境 deploy job 生效**（后端变量不用重建镜像；`VITE_*` 要走前端 workflow 重新构建）。批量灌入用 [`../11-parameter-store/put-params.sh`](../11-parameter-store/README.md)。⚠️ 耦合键成对改：`API_KEY`==`VITE_X_API_KEY`、`CATALOG_OCR_API_KEY`==`OCR_API_KEY`。（test 已灌入；uat/prod 以工作区根 `deploy-env/<env>/backend.env.example` 为底稿。）

### 用法

```
/opt/css-cicd/bin/deploy.sh <test|uat|prod> [action] [stack] [image_tag]
```

| 参数 | 取值 |
|------|------|
| action | `deploy`(默认) / `up` / `down` / `pull` / `migrate` / `ps` / `logs` / `restart` / `pytest`(仅test) / `render-env` |
| stack | `all`(默认) / `core`(=infra+backend) / `infra` / `backend` / `frontend` |
| image_tag | 不可变版本 tag 如 `test-v12`（CI 每次发布自增；手动推送为 `<env>-manual-<sha7>`）；缺省用浮动 `<env>` tag |

**`deploy` 的完整行为**：渲染 env → ECR 登录 → 逐栈 pull + up → 冒烟（backend `:8080/api/docs`、frontend `:80/`，重试 2 分钟）→ `docker image prune -f` → 写 `.last_good_<env>`。冒烟失败退出非 0 → CI 红。

### 人工上机的典型操作

```bash
cd /opt/css-cicd
./bin/deploy.sh test ps                            # 三栈容器状态
./bin/deploy.sh test logs backend                  # 后端最近 200 行日志
./bin/deploy.sh test render-env && ./bin/deploy.sh test restart   # 改完参数手动生效（不重新 pull）
./bin/deploy.sh test deploy frontend test-v12      # 手动回滚前端到指定版本
cat .last_good_test                                # 上次成功部署的 tag
```

### 新机器初始化

`../06-ec2/create-app-ec2.sh` 建机（user-data 自动装 docker+compose）→ 角色/标签脚本已含 → **跑一次 Backend workflow** 即完成 bundle 上传 + 首次部署。机器即"牲口"，重建成本≈半小时。

## 五、常见问题

| 现象 | 处理 |
|------|------|
| 实例不在 describe-instance-information 里 | 角色没挂 / 机器出不了网（查私有路由 NAT）/ Agent 没跑（Session 上机 `systemctl status amazon-ssm-agent`） |
| send-command 报 AccessDenied | 用错环境凭证，或目标机标签与环境不符——IAM 条件按设计拦截 |
| 命令超时（最长 20 分钟） | 首次 pull 大镜像可能超，重跑一次（层已缓存会快） |
| deploy 冒烟失败 | 看 Run Command Output / GitHub job 日志定位哪个栈没起来 |

## 六、注意点

- EC2 上的 `/opt/css` 是旧手动链路（部署包时代）残留，已退役可删；应急手动操作 = 上机执行 `/opt/css-cicd/bin/deploy.sh`；
- `down` infra 栈会丢 kafka 未消费的 2FA 验证码（kafka 不落盘，设计如此）；
- prod migrate 前 workflow 自动打 RDS 快照，但**人工核对 `alembic_version` 在代码迁移链上**不能省；
- 回滚入口优先走 GitHub（Run workflow + image_tag），手动回滚是应急用；
- 状态：test 机已配好 SSM Online；uat/prod 机器建后各跑一次 setup（或直接用 06 脚本建）。
