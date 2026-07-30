# 方案二：Serverless 优化方案（生产环境演进目标）

> 定位：在方案一上线后**分阶段演进**的优化目标——去掉自托管中间件、按需伸缩、消除单点、原生可观测，并把**消息队列从 Kafka 改为 SQS**。每阶段独立可回退，不要求一步到位。
> 只出方案，不创建资源。编制日期：2026-07-23。

---

## 1. 优化目标

| 维度 | 方案一（单机） | 方案二（Serverless） |
|------|----------------|----------------------|
| 计算 | 单台 EC2（单点） | Fargate 多副本 + 自动扩缩，无服务器运维 |
| 队列 | 自托管 Kafka（不落盘/需自管） | **SQS**（托管、持久、DLQ 原生） |
| 通知总线 | 自托管 RabbitMQ | Amazon MQ（托管 RabbitMQ）或重构 |
| 缓存/队列存储 | 自托管 Redis | ElastiCache（托管 Redis） |
| 定时任务 | 容器内 arq cron | EventBridge Scheduler 触发 |
| 前端 | EC2 上 nginx 容器 | S3 + CloudFront（全球 CDN + WAF） |
| 可观测 | 需自搭 | CloudWatch Logs/Metrics + Container Insights + X-Ray 原生 |
| 高可用 | 需双机 | 多 AZ 多副本天然 |

---

## 2. 组件 → 托管服务映射

> 服务清单来自 [services-inventory 实测]，逐个给出 serverless 落点与改造量。

| 现有组件 | 形态 | Serverless 目标 | 改造量 |
|----------|------|-----------------|--------|
| frontend（SPA + nginx） | 静态 | **S3 + CloudFront**（ACM 证书 + WAF；`/api`/`/ws` 经 CloudFront behavior 或直连 ALB） | 小：改发布为 sync S3 + invalidation |
| nginx（反代入口） | 基础设施 | **ALB**（路由 `/api`→app、`/ws`→messenger、`/notifications`→notifications） | 小：路由规则迁到 ALB，去掉 nginx 容器 |
| app（主 API，FastAPI） | ASGI | **ECS Fargate 服务**（≥2 副本，ALB target group，自动扩缩） | 小：容器化已就绪，去掉 gunicorn 单机假设 |
| messenger-app（`/ws` websocket） | ASGI | **Fargate 服务**（ALB 支持 WebSocket，sticky） | 小：Fargate 保留最省事（Lambda 不适合长连接） |
| notifications-app（RabbitMQ→WS 推送） | ASGI | **Fargate 服务** + Amazon MQ（或重构为 API Gateway WebSocket + SQS/SNS） | 中：保留 RabbitMQ→Amazon MQ 改动小；彻底重构改动大 |
| worker（arq，33 任务 + 6 cron） | 常驻 worker | **Fargate 服务**（arq 常驻）+ cron 拆到 EventBridge | 中：cron 迁 EventBridge；任务体不变 |
| **sms_sender**（Kafka 消费→Twilio） | Kafka consumer | **SQS 队列 `sms_send` + Lambda 消费**（SQS 事件源，DLQ 原生） | 中：见 §3 队列改造 |
| **email_sender**（Kafka 消费→SMTP，DLQ） | Kafka consumer | **SQS 队列 `email_send` + Lambda 消费 + SQS DLQ** | 中：见 §3；去掉自建 DLQ producer |
| kafka（KRaft broker） | 基础设施 | **删除**（被 SQS 取代） | — 消除自托管队列与"不落盘丢消息"风险 |
| redis（arq 队列 + 缓存） | 基础设施 | **ElastiCache for Redis**（托管，多 AZ） | 小：改连接端点 |
| rabbitmq（通知 fan-out） | 基础设施 | **Amazon MQ for RabbitMQ**（托管） | 小：改连接端点 |
| ai_assistant（Node/OpenAI） | HTTP 服务 | **Fargate 服务** 或 **Lambda**（无状态、按需） | 小 |
| ocr-api（FastAPI，OCR 作业 API） | ASGI | **Fargate 服务** | 小 |
| ocr-worker（arq + Gemini，长任务） | 常驻 worker | **Fargate 服务**（长跑作业不适合 Lambda 15 分钟上限） | 小 |
| ocr-db / db（Postgres） | 基础设施 | **RDS**（或 Aurora Serverless v2 按需伸缩） `css_prod`/`ocr_prod` | 小：方案一已 RDS |
| ocr-redis | 基础设施 | **ElastiCache**（独立实例或逻辑库） | 小 |
| ocr-migrator（一次性迁移） | 一次性 job | **ECS RunTask**（部署流水线触发） | 小 |
| kafka-ui / pgadmin | 管理 UI | **删除**（不进生产；用 CloudWatch/RDS 控制台/客户端隧道） | — |

**目标架构一句话**：CloudFront(前端) + ALB(路由) + Fargate(app/messenger/notifications/worker/ai/ocr-api/ocr-worker) + RDS/Aurora(库) + ElastiCache(Redis) + Amazon MQ(通知) + **SQS(短信/邮件 + DLQ)** + EventBridge(定时) + Secrets Manager + CloudWatch/X-Ray(可观测)。

---

## 3. 队列改造：Kafka → SQS（重点）

现状：`app`/`worker` 作为 producer 往 Kafka topic `sms_send`/`email_send` 发消息；独立消费者 `sms_sender`/`email_sender` 消费后调 Twilio/SMTP，`email_sender` 失败写 `email_send_dlq`。审计发现该链路有**丢消息**（每次启动新消费组 + `latest`，#8）、**毒丸崩溃循环**（#21）、**offset 提交名存实亡**（#45）等缺陷。

**目标**：
- topic `sms_send` → **SQS 标准队列 `css-prod-sms-send`** + **SQS DLQ**（`maxReceiveCount` 后转 DLQ，替代自建 `email_send_dlq`）。
- topic `email_send` → **SQS 队列 `css-prod-email-send`** + **SQS DLQ**。
- 生产者：`app`/`worker` 的 Kafka producer 抽象为 **queue publisher 接口**，实现切到 `boto3 sqs.send_message`（保留接口便于回退/测试）。
- 消费者：`sms_sender`/`email_sender` 从常驻 Kafka 消费循环改为 **Lambda（SQS 事件源映射）**——SQS 原生保证至少一次投递、可见性超时、失败自动重试→DLQ，**天然消除 #8/#21/#45 三个缺陷**；或过渡期先让现消费者进程改用 SQS 长轮询（改动更小）。

**改造要点**：
- 消息体：现 `EmailProducer` 有二次序列化问题（#20），迁 SQS 时统一为一次 JSON 序列化（消费端去掉 `ast.literal_eval`）。
- 幂等：SQS 标准队列至少一次投递，消费端对短信/邮件发送加幂等键（避免重复发验证码）；如需严格一次可用 FIFO 队列 + 去重 ID。
- 顺序：短信/邮件无强顺序要求，标准队列即可（吞吐更高）。
- 可观测：SQS 队列深度、DLQ 消息数、Lambda 错误率进 CloudWatch 告警。

> 该改造同时是[功能列表 §六技术债"队列改为 SQS"](../ocean-island/功能列表.md) 的落地，兼修 3 个消费者审计 bug。

---

## 4. WebSocket 处理（messenger / notifications）

- `messenger-app`（`/ws`）与 `notifications-app`（`/notifications`）是**长连接 WebSocket**，不适合 Lambda。两条路：
  - **A（推荐，改动小）**：保留为 **Fargate 服务**，ALB 支持 WebSocket + 会话粘滞；`notifications-app` 的 RabbitMQ 换 **Amazon MQ**。
  - **B（彻底 serverless）**：重构为 **API Gateway WebSocket API + Lambda + DynamoDB(连接表) + SQS/SNS 扇出**——改动大（需重写连接管理与推送逻辑），列为远期可选。
- 首期取 A，避免重写 WebSocket 层。

---

## 5. 定时任务（cron → EventBridge）

worker 现有 **6 个 arq cron**（每日安全码 ×2、`check_unregistered_clients`、`update_eden_ai_availability` 每分钟、餐厅相关等）+ OCR 的 `cleanup_expired_jobs`。

- 迁 **EventBridge Scheduler**：每个 cron → 一条 schedule，触发 **ECS RunTask**（跑一次性任务容器）或 Lambda。
- `update_eden_ai_availability`（每分钟）频率高，评估是否降频或保留 worker 内部调度。
- 好处：定时逻辑与常驻 worker 解耦，可观测、可单独重试。

---

## 6. 可观测性（对应技术债"日志/监控"）

- **日志**：所有 Fargate 任务 → CloudWatch Logs（结构化 JSON），按服务分组；保留策略。
- **指标**：Container Insights（CPU/内存/任务数）、ALB 5xx/延迟、RDS 连接/慢查询、SQS 深度/DLQ、ElastiCache 命中率。
- **追踪**：X-Ray 打通 ALB→app→RDS/SQS 调用链（可选，价值高）。
- **告警**：SNS 通知（5xx 突增、DLQ 非空、RDS CPU/连接高、任务重启循环）。
- **看板**：CloudWatch Dashboard 汇总核心指标。

> 这是[功能列表 §六技术债"增加日志/服务监控"](../ocean-island/功能列表.md) 的目标形态；方案一阶段可先接 CloudWatch Logs + 基础告警，方案二补齐全链路。

---

## 7. CI/CD 与 IaC

> CI/CD 同样由 **GitHub Actions** 触发驱动，设计见 **[03-CICD-GitHub-Actions.md](03-CICD-GitHub-Actions.md)**；与方案一共用构建/审批/密钥分层，仅"部署动作"不同。

- **镜像**：同 ECR（不可变 tag + 扫描）；GitHub 托管 runner 经 **OIDC** 假设 AWS 角色构建推送（免静态密钥）。
- **部署**（方案一是 SSM 触发 `deploy.sh`，本方案替换为）：`aws ecs update-service --force-new-deployment`（滚动）或 **CodeDeploy 蓝绿**（两 target group 切流，零停机）。
- **迁移**：`deploy` 前独立 job `aws ecs run-task` 跑一次性 migrate 任务（先打 RDS 快照 + `alembic_version` 核对）。
- **审批**：生产部署走 GitHub Environment `main` + Required reviewers（2026-07-29 起 environment 名=分支名 test/uat/main）。
- **IaC**：全栈 Terraform/CDK（VPC/ALB/ECS/RDS/ElastiCache/MQ/SQS/EventBridge/IAM/CloudFront/WAF），prod 从第一天纳管，杜绝控制台手改。

---

## 8. 分阶段迁移路径

> 每阶段独立上线、可回退；先拿方案一稳定运行，再逐步演进。

| 阶段 | 内容 | 收益 |
|------|------|------|
| P1 | 前端迁 **S3+CloudFront**；后端 app/messenger/notifications/worker/ocr 迁 **Fargate**（+ALB）；DB 用 RDS（已有）；Redis→ElastiCache、RabbitMQ→Amazon MQ | 去应用单点、按需伸缩、原生日志 |
| P2 | **Kafka→SQS**：sms/email 队列转 SQS + Lambda 消费 + DLQ，删除自托管 Kafka；顺带修 3 个消费者 bug（#8/#21/#45/#20） | 消除丢消息/崩溃循环，去自托管队列 |
| P3 | cron→**EventBridge**；补齐 **X-Ray + Dashboard + 告警**；CodeDeploy 蓝绿 | 全可观测、零停机发布 |
| P4（可选） | Aurora Serverless v2；notifications 重构为 API Gateway WebSocket；成本优化（Savings Plan/Fargate Spot 非关键任务） | 更弹性、更省 |

---

## 9. 成本 / 复杂度权衡

- **成本**：Fargate 常驻多服务 + ElastiCache + Amazon MQ 有**固定基线**，轻负载下**可能高于**方案一单机（单机 ~$320~360/月）；但换来高可用、免运维、按需伸缩。SQS/EventBridge/CloudFront 按量计费、量小几乎免费。
- **复杂度**：组件更多、需 IaC 与 CI/CD 成熟度；WebSocket 与 Amazon MQ 是主要迁移难点。
- **代码改动**：主要在**队列抽象层（Kafka→SQS）**与连接端点（Redis/RabbitMQ→托管）；应用业务逻辑基本不动（已容器化）。
- **建议**：Ocean Island 上线初期负载不高，**方案一足够且更省**；当可用性 SLA、伸缩需求或运维负担上升时，按 P1→P4 演进到方案二。

---

## 10. 风险与限制

- **WebSocket**：Lambda 不适合长连接，messenger/notifications 首期须留 Fargate（或重构成本高）。
- **SQS 语义**：标准队列至少一次投递 → 发送侧必须幂等（尤其验证码/邮件），否则重复发送。
- **Amazon MQ 成本**：托管 RabbitMQ 有基线成本；若 notifications 重构为 SNS/SQS+API GW 可省，但改动大。
- **迁移期双跑**：P1/P2 迁移期需 Kafka 与 SQS、RabbitMQ 与 Amazon MQ 并存灰度，需谨慎切流与回退预案。
- **arq 依赖 Redis**：worker 任务队列仍需 Redis（ElastiCache），无法用 SQS 完全替代 arq（arq 的任务编排/重试语义与 SQS 不同）。
