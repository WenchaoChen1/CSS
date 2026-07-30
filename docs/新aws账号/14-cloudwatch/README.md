# 14-cloudwatch —— 监控告警 + 日志收集（两者均已落地 ✅）

`create-monitoring.sh <test|uat|prod> [告警邮箱] [--with-agent]`
一条命令给一个环境配齐：**告警（Alarms）→ 通知（SNS 邮件）→ 仪表盘（Dashboard）**。
资源带 `Group` + `CssEnv` 双标签，幂等可重复执行。

```bash
cd docs/新aws账号/14-cloudwatch
./create-monitoring.sh test ops@example.com     # 已执行 ✅
./create-monitoring.sh uat  ops@example.com     # 已执行 ✅
./create-monitoring.sh prod ops@example.com --with-agent   # ⏳ 等生产机建好
```

> 首次带邮箱执行后，AWS 会发一封订阅确认邮件——**必须点里面的确认链接**，否则告警发不出来。
> 现在两套告警的 SNS 主题（`css-test-alarms` / `css-uat-alarms`）**还没有任何订阅者**，
> 告警会触发但没人收得到。给我一个邮箱我就补上，或你自己在 SNS 控制台加。

## 已配的 9 条告警（每环境）

| 告警 | 触发条件 | 为什么盯这个 |
|------|---------|-------------|
| `ec2-cpu-high` | CPU 连续 15 分钟 >80% | 死循环、负载过大 |
| `ec2-status-check` | 状态检查失败 2 个周期 | 实例或底层宿主机故障，**缺数据也算告警**（机器没了指标就停了） |
| `ec2-cpu-credit-low` | CPU 积分 <20（仅 t 系列） | 突发型实例积分耗尽会被限速到基线，表现为"莫名其妙变慢" |
| `rds-cpu-high` | 数据库 CPU >80% 持续 15 分钟 | 慢查询、缺索引 |
| `rds-memory-low` | 可用内存 <100MB | **本实例最紧的资源**——实测 t4g.micro 只剩约 146MB，再低就开始换页、查询雪崩 |
| `rds-storage-low` | 剩余存储 <2GB | 写满会让数据库直接进入 storage-full 只读状态 |
| `rds-connections-high` | 连接数 >80 | t4g.micro 上限约 100，打满后新连接全被拒 |
| `alb-no-healthy-target` | 健康目标数 <1 持续 3 分钟 | **最有价值的一条**：它比 5xx 更早、更确定地说明"服务已经不可用" |
| `alb-5xx` | 5 分钟内后端 5xx >10 次 | 应用报错 |
| `alb-latency-high` | 后端响应 P95 >3 秒 | 性能劣化 |

**注意 EC2 的内存和磁盘使用率不在里面**——那不是 AWS 的基础指标，宿主机看不到客户机内部。
要监控必须在机器上装 CloudWatch Agent（`--with-agent`），脚本会顺带再建 `ec2-mem-high`（>85%）
与 `ec2-disk-high`（>85%）两条告警。**准确成本不止 $0.6**：

| 项 | 计算 | 金额 |
|----|------|------|
| 自定义指标 | 2 个 × $0.30/月 | $0.60 |
| PutMetricData 请求 | 288 次/天 × 30 天 ÷ 1000 × $0.01 | $0.09 |
| 两条新告警 | 2 × $0.10 | $0.20 |
| | **合计** | **≈ $0.89 / 月 / 台机器** |

三台全开约 $2.7/月；只给 prod 开约 $0.9/月。**当前未开启**，等你确认。

## 成本

| 项 | 单价 | 每环境 |
|----|------|--------|
| 告警 | $0.10/个/月 | 9 个 → **$0.90** |
| Dashboard | 前 3 个免费 | $0 |
| SNS 邮件 | 每月前 1000 封免费 | $0 |
| 基础指标（5 分钟粒度） | 免费 | $0 |
| （可选）Agent 全套 | 指标+请求+告警 | +$0.89/机 |
| | **合计** | **≈ $1/月**（开 Agent 约 $1.9） |

## 可视化页面

- **告警列表**：<https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#alarmsV2:>
  看什么：状态列 OK / ALARM / **INSUFFICIENT_DATA**。刚建完是 INSUFFICIENT_DATA 属正常，
  要等指标攒够评估周期（5-15 分钟）；uat 未部署时 `alb-no-healthy-target` 会转 ALARM，这是对的。
- **仪表盘**：<https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards/>
  `css-test` / `css-uat` 各一个，一屏看完 CPU / 内存 / 连接数 / 请求量 / 5xx / 健康目标数。
- **SNS 订阅**：<https://us-east-1.console.aws.amazon.com/sns/v3/home?region=us-east-1#/topics>
  确认邮箱状态是 **Confirmed** 而不是 PendingConfirmation。

---

# 日志收集（CloudWatch Logs）—— ✅ 2026-07-29 已落地

按"要能以**整个 test / uat / prod 环境**的方式查询日志"的要求实施完毕。

## 日志组怎么划分：一个环境一个组

```
/css/test    ← 该环境全部 17 个容器的日志都在这里，保留 7 天
/css/uat     ← 保留 14 天
/css/prod    ← 保留 30 天（待生产上线时建）
```

服务不靠日志组区分，而是靠 **log stream 名 = 容器名**（compose 里 `tag: "{{.Name}}"`）：

```
/css/test
├── css-test-backend-app-1
├── css-test-backend-nginx-1
├── css-test-backend-worker-1
├── css-test-frontend-frontend-1
├── css-test-infra-kafka-1
└── …（共 17 个流）
```

**为什么这么分**：你要的是"按整个环境查"。如果按服务拆成 9 个日志组，查一次全环境就得勾 9 个组，
正好和需求相反；而合成一个组后，查全环境只选一个组，查单服务加一句 `filter` 就行——两个方向都顺。
代价是保留期只能按环境统一设（不能给 nginx 设 3 天、给 app 设 30 天），对目前规模不是问题。

## 怎么查（Logs Insights）

控制台：<https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:logs-insights>
选日志组 `/css/test`，然后：

```sql
-- ① 整个环境最近发生了什么（按时间倒序看全部服务）
fields @timestamp, @logStream, @message | sort @timestamp desc | limit 100

-- ② 各服务日志量分布（实测结果：kafka 841 条、rabbitmq 175、backend-app 14…）
fields @logStream | stats count() as cnt by @logStream | sort cnt desc

-- ③ 只看后端应用
fields @timestamp, @message | filter @logStream like /backend-app/ | sort @timestamp desc

-- ④ 全环境找错误（跨所有容器，这是单日志组最大的价值）
fields @timestamp, @logStream, @message
| filter @message like /ERROR|Traceback|500 |Exception/
| sort @timestamp desc | limit 50

-- ⑤ 追一个请求在多个容器间的完整链路
fields @timestamp, @logStream, @message | filter @message like /<request-id>/ | sort @timestamp asc

-- ⑥ 登录失败趋势（排查 salt / 2FA 问题）
fields @timestamp | filter @message like /sign-in/ and @message like /401|403/
| stats count() by bin(5m)
```

命令行同样可用：

```bash
aws logs start-query --region us-east-1 --log-group-name /css/test   --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s)   --query-string 'fields @timestamp, @logStream, @message | sort @timestamp desc | limit 20'
# 拿返回的 queryId 再 get-query-results
```

> ⚠️ Windows 上写查询语句**别用中文别名**（`stats count() as 日志条数`）——aws.exe 用 GBK 传参会把它打成乱码，
> 报 `MalformedQueryException: token recognition error`。用英文别名（`as cnt`）。

## 落地做了什么

| 步骤 | 内容 | 脚本 |
|------|------|------|
| 1 | 建日志组 + 设保留期 + 打双标签 | `setup-logs.sh <env> [天数]` ✅ test/uat 已建 |
| 2 | 给实例角色加**只写本环境日志组**的权限（故意不给 `CreateLogGroup`——让容器自动建组会建出永不过期的组） | 同上，策略 `css-ec2-<env>-logs` |
| 3 | 三个 compose 的 `x-logging` 从 `json-file` 换成 `awslogs` | `deploy/compose/{infra,backend,frontend}.yml` ✅ |
| 4 | 重新部署并验证 | `deploy-env.sh test` ✅ 17 个流全部产生 |

compose 里的最终配置：

```yaml
x-logging: &logging
  driver: awslogs
  options:
    awslogs-region: us-east-1
    awslogs-group: /css/${DEPLOY_ENV:?}
    awslogs-create-group: "false"   # 组由脚本预建并设好保留期
    tag: "{{.Name}}"                # log stream 名 = 容器名
    mode: non-blocking              # 网络抖动时不阻塞容器（默认 blocking 会拖垮应用）
    max-buffer-size: 4m
```

## 代价与注意

- **`docker logs` 失效了**：日志不再落本地磁盘。上机查日志改用 Logs Insights，或临时把某个服务
  的 driver 改回 json-file。这是 awslogs 驱动的固有取舍。
- **保留期一定要设**：日志组默认永不过期，费用会无限累积。脚本已按环境设好（7/14/30 天）。
- **别开 DEBUG**：`LOG_LEVEL` 保持 20(INFO)。开 DEBUG 日志量能翻十倍，直接体现在账单上。
- 超过保留期还要留的（如审计），用 Logs → S3 导出 + Glacier（$0.004/GB/月），比留在 Logs 里便宜一个数量级。

## 成本

摄入 $0.50/GB、存储 $0.03/GB/月、Insights 查询 $0.005/GB 扫描。

| 环境 | 估算量 | 月成本 |
|------|--------|--------|
| test | ~1 GB/月 | ≈ $0.5 |
| uat | ~1 GB/月（部署后） | ≈ $0.5 |
| prod | ~10 GB/月 | ≈ $5.3 |
| | **合计** | **≈ $6.3/月** |

## 状态

- ✅ **test**：日志组 `/css/test`（7 天）+ 17 个容器流全部产生，实测一条查询覆盖全环境 1384 条日志。
- ✅ **uat**：日志组 `/css/uat`（14 天）+ 权限已就绪，等 uat 部署后自动产生流。
- ⏳ **prod**：等生产机建好后 `./setup-logs.sh prod`。
