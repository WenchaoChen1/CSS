# 012 WebSocket 鉴权会话泄漏：长期占着 user 表锁，导致迁移卡死、部署失败

| 项 | 内容 |
|----|------|
| 状态 | 待优化 |
| 优先级 | P0（卡死登录与全部鉴权接口；test / uat / prod 代码相同，prod 部署同样会中招） |
| 涉及代码 | `notifications/auth/middleware.py`、`messenger/auth/middleware.py`、`core/auth/tokens/transport/di.py`、`pkg/databases.py`、`notifications/transport/handlers.py`、`notifications/rabbitmq/{connector,consumer}.py`、`messenger/chats/transport/{handlers,di}.py`、`migrations/env.py` |
| 涉及表 | `user`、`issued_token`（及其全部索引）——被泄漏事务持有 `AccessShareLock` |
| 数据来源 | uat RDS `css-uat-main` 2026-10-19 15:17 实时 `pg_stat_activity` / `pg_locks`；本机复现（test 数据库副本） |
| 代码基线 | 后端 `origin/uat` @`3ba2ac02`（2026-10-19 15:06，PR #76） |
| 发现日期 | 2026-10-19 |
| 在线版 | https://claude.ai/artifact/52sVA2bVUXiP2hw4oh73ud（给开发看的页面；本地不留 html，以本文为准） |

## 一、现在是什么问题

### 1. 现象（2026-10-19 uat，北京时间）

| 时间 | 会话 | 事件 |
|------|------|------|
| 13:50 | — | sprint5 合入 `uat`（PR #75），CI：build → migrate → deploy |
| 13:53:54 | 12842 | 旧版应用（10-16 部署）的一个连接执行了 WebSocket 鉴权：`SELECT issued_token…`、`SELECT "user"…`，之后**进入 `idle in transaction`，不提交也不回滚**，持有 `user`、`issued_token` 及其所有索引的 `AccessShareLock` |
| 13:56:46 | 17158 | CI 迁移 `a4f1c7e92b58` 执行到 `ALTER TABLE payment_method DROP COLUMN created_by_user_id`。该列有指向 `user` 的外键，删外键要拿 **`user` 的 `AccessExclusiveLock`**，因此开始等 12842 |
| 之后 | 31+ 个 | PG 的锁是排队的：后来的所有 `SELECT "user"…`（登录、每个鉴权接口）都排在 17158 后面 → **uat 全站接口挂起** |
| ~14:16 | — | CI migrate 只等 20 分钟（`deploy/aws/ssm-run.sh` 240×5s）→ 判失败 → **deploy 被跳过**，线上一直是 10-16 旧版 |
| 14:29 / 15:13 | 22912 / 30680 | 重跑的迁移又排在前一个后面（`ALTER TYPE paymentmethod ADD VALUE 'MONEY_ORDER'` 被前一个未提交事务锁住） |
| 15:31 | — | 运维结束 3 个卡住会话（见「三、处理记录」），uat 恢复 |

### 2. 根因（代码）

**R1（主因）WebSocket 鉴权用的数据库会话活得和 WebSocket 一样久。**

```
check_access_token_ws(...)                       # notifications 与 messenger 各有一份，内容相同
  └─ tokens_service = Depends(get_tokens_service)
       └─ session = Depends(get_session)         # pkg/databases.py：async with async_session() as session: yield session
verify_access_token()                            # 查 issued_token（是否吊销）+ 查 user（是否存在）
  → SQLAlchemy 自动开启事务，之后没有 commit / rollback
```

- FastAPI 对 WebSocket 端点的 `yield` 依赖，要等端点函数**返回**才清理。
- notifications 端点是 `while True` 每 5 秒轮询一次，只要页面开着就不返回，所以这个事务**页面开多久就挂多久**（`idle in transaction`），一直占着 `user` / `issued_token` 的锁，也一直占着连接池里的一个连接。
- messenger 是路由级依赖 `Security(check_access_token_ws)`，聊天业务的 repository 也用同一个请求级会话（FastAPI 同一请求内依赖缓存）：从连上到第一次 `commit` 之间挂着事务，之后只读不提交的操作也会继续挂。

**R2（放大）迁移没有锁等待上限。**

需要 `user` 独占锁的 DDL（删 / 改指向 `user` 的外键、给 `user` 加删改列、加约束等）只要碰上任何一个开着的页面，就会无限等待；它在锁队列里挡住后面所有读 `user` 的请求，于是**一次迁移把全站拖死**。`migrations/env.py` 没有设置 `lock_timeout`。

**R3（放大）CI 超时后，迁移没被真正停掉。**

CI 20 分钟后判失败，但 uat 机上的迁移容器 / PG 会话还活着（17158 挂了 1 小时以上），每次重跑只会继续排队。

**R4（仅 Windows 本地开发机）notifications 断开后循环永不退出。**

断开检测写的是 `await asyncio.wait_for(websocket.receive_text(), timeout=0.01)`。Windows 的时钟精度是 15.6 ms，比 10 ms 超时还粗，asyncio 会立刻判超时：

| 环境 | 时钟精度 | `wait_for(..., timeout=0.01)` 200 次 |
|------|----------|--------------------------------------|
| Windows（本地开发机） | 15.6 ms | 拿到结果 **0** 次，超时 200 次 |
| Linux（uat / prod 容器） | 1 ns | 拿到结果 200 次 |

所以本地 Windows 上关掉页面后，循环照转、事务和 RabbitMQ 连接永不释放，直到进程重启。Linux 上能检测到断开，但这段循环还有其他问题：`except (TimeoutError, RuntimeError): pass` 会吞掉异常；`consumer.close()` 和 `manager.disconnect()` 不在 `finally` 里；`RabbitMQConnector.close()` 先关连接再关通道（顺序反了）；每 5 秒对不存在的队列做一次被动声明，收到 404 后通道被关再重开。

**附带问题：** `get_redis_client()` 每次请求都新建 Redis 客户端、从不关闭（每个 WebSocket 一个）。

### 3. 证据

- **uat 实时数据**：12842 为 `idle in transaction` 持续 1 小时 38 分，持有锁 = `user`、`user_pkey`、`user_email_key`、`user_phone_number_key`、`uq_user_email_lower`、`ix_user_created_at`、`issued_token`、`issued_token_pkey`。这正是 `verify_access_token` 两条查询会碰到的全部对象。
- **本机复现**（相同代码，test 数据副本）：登录拿 token → 打开 `ws://localhost:8002/notifications/ns/store/manager`。
  - 打开前：无 `idle in transaction`。
  - 打开 8 秒：出现 1 个，锁对象与 uat 的 12842 完全一致。
  - 关闭 2 分钟后：仍在，RabbitMQ 消费连接也仍是 running（Windows，见 R4）。
- **打点**：关闭后 `receive_text` 一次异常都没抛、`consumer.close()` 从未进入，循环每 5 秒照常执行 `get_single_message`。

### 4. 影响与风险

- **部署**：test / uat / prod 代码相同。以后任何迁移只要需要 `user` 或 `issued_token` 的独占锁，碰上有人开着页面就会卡死并拖垮全站。prod 是手动触发部署，会直接变成**线上事故**。
- **连接池**：每个开着的页面长期占 1 个数据库连接。SQLAlchemy 默认每进程 `pool_size=5 + max_overflow=10`，并发页面一多，notifications / messenger 就拿不到连接。连接也计入 RDS `max_connections`，非生产实例是 181，由 5 个环境共用。
- **本地开发**：Windows 上每关一次页面，就泄漏 1 个事务 + 1 个 RabbitMQ 连接，直到进程重启。

## 二、怎么处理（方案）

### 1. 改动总览

| 编号 | 改动 | 解决 | 负责 | 必要性 |
|------|------|------|------|--------|
| B1 | WebSocket 鉴权改用「用完即关」的独立会话；两份 `check_access_token_ws` 合并为一份 | R1 | 开发 | 必做（根治） |
| B2 | messenger 业务改为「每个事件一个会话」 | R1 | 开发 | 必做 |
| B3 | notifications 循环重写：可靠检测断开 + `finally` 释放；RabbitMQ 改订阅式消费 | R4 及循环缺陷 | 开发 | 必做 |
| B4 | 迁移统一设置 `lock_timeout`（默认 10s） | R2 | 开发 | 必做（防护，改动最小，可先上） |
| B5 | 迁移编写规范：热表独占锁的 DDL 单独成迁移 | R2 | 开发 | 必做（规范） |
| B6 | 迁移前清理残留迁移容器 + 迁移整体超时 | R3 | 运维 | 建议 |
| B7 | 应用账号设置 `idle_in_transaction_session_timeout` 兜底 | 兜底 | 运维 | 建议（B1–B3 上线后再开） |

### 2. 数据迁移

无数据变更、无表结构变更。

### 3. 后端改动（开发）

**B1 WebSocket 鉴权：会话只在校验期间存在。**

- 新增一个共用的鉴权函数（建议放 `core/auth/tokens/transport/`），内部自己开、自己关会话：

  ```python
  async def verify_ws_access_token(token: str) -> Result[TokenDataDTO, Error]:
      async with async_session() as session:          # 退出即 close（未提交的事务自动回滚）
          tokens_service = TokensService(
              jwt_service=JWTService(config=auth_settings.jwt_config),
              tokens_repository=TokensRepository(session=session),
              users_repository=UsersRepository(session=session),
              session_service=get_session_service(redis_client=redis_client),  # 复用模块级 Redis 客户端
          )
          return await tokens_service.verify_access_token(token=token)
  ```

- `check_access_token_ws` 去掉 `tokens_service: TokensService = Depends(get_tokens_service)` 参数，改调上面的函数。notifications 和 messenger 两份完全相同的中间件**合并为一份**（放 `pkg/websockets/` 或 `core/auth/`），两边都引用它。
- 顺手修附带问题：`get_redis_client()` 改为模块级单例（或在 lifespan 里创建 / 关闭），不要每个请求新建。
- **注意**：HTTP 接口的 `get_tokens_service` / `get_session` 不用改，HTTP 请求结束就会释放会话。只改 WebSocket 路径。

**B2 messenger：每个事件一个会话。**

- 当前 `get_chat_messages_service` → `get_chats_service` → `get_chats_repository(Depends(get_session))`，整个 WebSocket 生命周期共用一个会话。
- 改为：端点只拿 `user_id` / `device_id`，在 `while True` 循环里**每收到一个事件**就 `async with async_session() as session:`，用这个会话组装 service、处理事件、提交，退出时会话关闭。
- `close_all_chats_for_connection`（断开时调用）同样用独立会话。
- 如果改动面太大，最低要求是：每个事件处理完都显式 `commit()` 或 `rollback()`，不留未结束的事务。

**B3 notifications 循环重写。**

- 断开检测不要再用 `wait_for(..., timeout=0.01)` 轮询。改为两个并发任务：
  - 一个任务专门 `await websocket.receive()`，直到收到 `websocket.disconnect`；
  - 另一个任务消费 RabbitMQ 并 `send` 给前端；
  - 用 `asyncio.wait(..., return_when=FIRST_COMPLETED)`，任何一个结束就取消另一个。
- 整个端点包在 `try / finally` 里：`finally` 中**一定**执行 `manager.disconnect(...)` 和 `consumer.close()`。不要再吞 `RuntimeError`。
- RabbitMQ 改为订阅式：`declare_queue(routing_key, durable=True)`（与 publisher 一致，不再被动声明、不再 404），然后 `async with queue.iterator() as it: async for message in it: ...`，替代每 5 秒 `get_queue` + `get(timeout=5)` 的轮询。
- `RabbitMQConnector.close()` 改为先关通道再关连接，并做成幂等（已关闭则跳过）。

**B4 迁移设置锁等待上限（可最先上线，独立小改动）。**

`migrations/env.py` 是异步写法（`run_async_migrations()` → `async_engine_from_config(...)` → `connection.run_sync(do_run_migrations)`）。最简单的做法是建连接时就带上会话参数，不碰事务管理：

```python
connectable = async_engine_from_config(
    config.get_section(config.config_ini_section, {}),
    prefix='sqlalchemy.',
    poolclass=pool.NullPool,
    connect_args={'server_settings': {'lock_timeout': '10s'}},   # asyncpg：连接建立时即 SET
)
```

（不要在 `do_run_migrations` 里直接 `connection.execute(text("SET ..."))`：SQLAlchemy 2.x 会因此自动开启事务，干扰 alembic 的 `transaction_per_migration`。）

- 效果：拿不到锁 10 秒就报 `canceling statement due to lock timeout` 并回滚（`transaction_per_migration=True`，只回滚当前这一个迁移），CI 立刻显示失败，**不会再把全站拖死**。
- 个别确实需要等更久的迁移，可在自己的 `upgrade()` 开头写 `op.execute("SET LOCAL lock_timeout = '60s'")` 覆盖。

**B5 迁移编写规范（写进 PR 检查项）。**

- 需要热表（`user`、`issued_token`、`order`、`company` 等）**独占锁**的操作要单独成一个迁移，不和其他改动放一起。例如：删 / 改指向这些表的外键、给这些表加删改列、在这些表上加约束。
- 删除带外键的废弃列，优先「先保留，代码不再读写」，再择机单独删除。`a4f1c7e92b58` 在提交 `043a1bd4` 里就是这样处理的，保留这个做法。
- 新增外键（`ShareRowExclusiveLock`）和读请求不冲突，但会和对该表的写冲突。数据量大时用 `NOT VALID` + 单独一步 `VALIDATE CONSTRAINT`。

### 4. 前端改动

无。WebSocket 协议不变：token 仍走 `Sec-WebSocket-Protocol`，路径不变。

### 5. 环境与发布注意

- **分支**：修复走开发分支 → 合 `uat`，再**分别**合 `test` 和 `main`。不要从 `test` 合到 `uat`：test 带老团队迁移线，会把 uat 的 alembic 头带偏。
- **上线顺序**：B4 可以先单独上；B1 + B3 一起上（都在 notifications）；B2 随后。
- **上线即清理**：部署会重启 notifications / messenger 进程，存量泄漏会话随之释放。
- **运维配合**：
  - B6：`deploy.sh migrate` 启动前清掉残留的迁移容器；迁移整体加超时，与 CI 等待时间对齐。
  - B7：B1–B3 在某环境上线后，对该环境执行 `ALTER ROLE css_app_<env> SET idle_in_transaction_session_timeout = '5min'`。**先上线代码再开**，否则 messenger 现有的长会话会被提前杀掉、报错。

### 6. 验收标准

1. **notifications**：打开 notifications WebSocket 并保持 60 秒，期间 `pg_stat_activity` 中该应用账号 `state = 'idle in transaction'` 的会话数为 **0**。关闭后 10 秒内，`rabbitmqctl list_connections` 里对应连接消失。**Windows 与 Linux 都要验**。
2. **messenger**：连上后、以及每处理完一个事件后，没有存活超过 1 秒的 `idle in transaction`。
3. **锁冲突演练**（任一测试库）：保持一个 notifications WebSocket 打开，执行一个需要 `user` 独占锁的测试迁移（如 `ALTER TABLE "user" ADD COLUMN _probe int`，验后删除），**立即完成、不排队**。
4. **lock_timeout**：另开 psql `BEGIN; LOCK TABLE "user" IN ACCESS SHARE MODE;` 不提交，再跑上面的测试迁移，约 **10 秒内失败**，报 `lock timeout`，且期间其他接口正常响应。
5. **自动化测试**：
   - 鉴权中间件测试：断言校验完成后会话已关闭；
   - notifications 端点测试：客户端关闭后端点函数返回，`consumer.close()` 与 `manager.disconnect()` 各被调用一次（mock）。
6. **上线后巡检**：uat 工作时间内抽查 3 次，下面这条查询结果都为 0。

   ```sql
   select count(*) from pg_stat_activity
   where usename = 'css_app_uat' and state = 'idle in transaction'
     and now() - state_change > interval '1 minute';
   ```

   部署迁移不再出现「migrate 超时 → deploy 跳过」。

### 附：本机复现脚本要点（开发自测用）

1. 正常登录拿 `access_token`（`/api/auth/sign-in/pre` → `/verify/contact` → 从本地库 `confirmation_code` 表取码 → `/verify/contact/code` → `/sign-in`）。
2. 用 `websockets.connect("ws://localhost:8002/notifications/ns/store/manager", subprotocols=[access_token])` 连上，注意路径前缀是 `/notifications`。
3. 期间用下面这条 SQL 看泄漏；关闭后再看一次。

   ```sql
   select pid, now() - xact_start, left(query, 60) from pg_stat_activity
   where datname = current_database() and state = 'idle in transaction';
   ```

## 三、处理记录

- **2026-10-19 13:56–15:31** uat 部署卡死，排查定位到本问题。
- **2026-10-19 14:58** 开发提交 `043a1bd4`：`a4f1c7e92b58` 不再删除 `payment_method.created_by_user_id`，规避 `user` 独占锁。随 PR #76 于 15:06 合入 uat。
- **2026-10-19 15:31** 运维应急（方案 A）：按语句内容核对后，结束卡住的迁移会话 22912、30680 与泄漏会话 12842（17158 此前已自行结束）。uat alembic 保持 `a6a624a6b564`，数据无变化，接口恢复（< 1 秒）。随后由负责人手动重跑 uat workflow。
- 根治（B1–B7）：**待开发排期**。
