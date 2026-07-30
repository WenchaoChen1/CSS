# 05-数据同步 —— RDS 建库 + 库到库数据同步 + 本地备份恢复 + 非生产脱敏

四个脚本：`create-databases.sh` 在 RDS 实例上按规范建各环境业务库（ocr 库自动加 pgvector）；`sync-db.sh` 用 pg_dump→pg_restore 流式把源库数据同步到目标库（这两个需在 VPC 内执行，PG 客户端经 `docker run postgres:16` 提供）；`restore-dump-via-gw.sh` 在**本机**执行，把本地 pg_dump 备份经 S3+SSM 由网关机恢复进私网 RDS（无需上机）；**`anonymize-db.sh` 给非生产库脱敏**（导入真实数据后必跑，见下）。

## 怎么用

```bash
# 1) 建库（库名规范 2026-07-28 拍板：css-<env>-main / css-<env>-ocr）
./create-databases.sh <rds主机> '<master密码>' test uat      # 非生产实例建 test+uat 四个库
./create-databases.sh <rds主机> '<master密码>' prod          # 生产实例建 prod 两个库

# 2) 同步数据（源 DSN → 目标 DSN）
./sync-db.sh 'postgresql://postgres:PASS@old-host:5432/css_test' \
             'postgresql://postgres:PASS@new-host:5432/css-test-main'
```

典型用途：本地 preprod 备份 → 新实例 `css-non-prod` 的 `css-test-main`/`css-test-ocr`（✅ 已用 restore-dump-via-gw.sh 完成）；test 数据 → uat 库作验收基线。

- ⚠️ create-databases.sh / sync-db.sh **必须在 VPC 内机器上执行**（RDS 在私有子网，本机不可达）——上应用机或经网关机隧道，需 Docker；本机场景用 restore-dump-via-gw.sh。
- ⚠️ `sync-db.sh` 带 `--clean --if-exists`，目标库同名对象会先被清掉；**生产同步前先打快照**。
- master 密码从 Secrets Manager 取（`rds!` 前缀 secret），命令行传参即可，勿写进文件。
- 库名含连字符，SQL 内脚本已用双引号处理；DSN 里可直接使用。
- ⚠️ **PG 版本对应**：导数据前核对源/目标 **大版本**（新实例 PG16.14），pg_dump/pg_restore 客户端版本**不得低于服务端大版本**；跨大版本恢复前先在测试库演练。

## restore-dump-via-gw.sh —— 本地备份经网关机恢复进私网 RDS

本地无法直连私有子网 RDS 时用（✅ 2026-07-28 已用它把 preprod 备份载入 test 库）。链路：

```
本地 pg_dump -Fc 备份 → S3 中转桶 css-dbsync-<账号>（私有+加密，自动创建）
  → SSM Run Command 在网关机上执行：装 psql16 客户端 → 从 Secrets Manager 自取 RDS 托管密码（密码不出 AWS）
  → 建库（css-<env>-main / css-<env>-ocr，ocr 自动加 pgvector）→ pg_restore → 清理（S3 dump 用完即删）
```

```bash
./restore-dump-via-gw.sh <test|uat|prod> <main库dump> <ocr库dump>
# 例（已执行）：
./restore-dump-via-gw.sh test ../../../备份/数据库/preprod/preprod_main_xxx.dump \
                              ../../../备份/数据库/preprod/preprod_ocr_xxx.dump
```

- 前置：网关机已由 `06-ec2/create-gateway.sh` 建成并挂 `css-gw-non-prod` / `css-gw-prod` profile（SSM + 读 css-dbsync 桶 + 读 `rds!` secret）——nonprod=css-non-prod-gw ✅；prod 用 css-prod-bastion。
- 目标是 prod 时脚本要求输入 `prod` 二次确认（覆盖恢复生产库）。
- 同样遵守上面的 PG 版本对应注意（脚本在网关机装的是 psql16，匹配新实例 PG16）。

## anonymize-db.sh —— 非生产脱敏（导入真实数据后**必须**执行一次）

从 preprod/生产导入的库里全是真人邮箱、手机号和真实口令哈希。**非生产环境不允许留真实个人数据**，
恢复完必须跑一次脱敏。`prod` 参数脚本会**直接拒绝执行**。

```bash
./anonymize-db.sh <test|uat> [口令]     # 口令缺省 Test1234!
# 已执行（2026-07-29）：
./anonymize-db.sh test
```

做了三件事（动态遍历 `information_schema` 找列，只认 `text`/`varchar`/`char`，排除列名含 `type` 的枚举字段）：

| # | 对象 | 处理 | 效果 |
|---|------|------|------|
| 1 | 所有 **email** 类文本列 | 值**前面加 `1`** → `1foo@bar.com` | 发不出去，也认不出是谁；已加过前缀的跳过（幂等） |
| 2 | 所有 **phone** 类文本列 | 值**后面加 `1`** | 打不通 |
| 3 | 所有 **password_hash** 列 | 统一为口令 **`Test1234!`** 的哈希 | 所有账号一个口令，方便测试 |

哈希算法取自目标环境的 `deploy-env/<env>/backend.env`：`pbkdf2_hmac(PASSWORD_HASH_ALGORITHM, 口令, PASSWORD_SALT, PASSWORD_HASH_ITERATIONS)`
= sha256 + env 里的 `PASSWORD_SALT` + **10 万次迭代**。**盐必须与运行环境一致**，否则改完仍然登录不上——历史踩过这个坑
（导入的用户用的是原团队的 salt，而 env 里是随机 salt，结果登录全挂）。密码明文只在本机参与计算，不进 AWS 日志。

**执行链路**：本机算哈希 → SSM Run Command 发到该环境应用机（按标签 `CssEnv=css-<env>` 定位，机器在 VPC 内能连 RDS）
→ 机器上读 `/opt/css-cicd/env/<env>/backend.env` 取库连接 → `docker run postgres:16 psql` 生成并在**单事务**里执行全部 UPDATE → 前后各抽样校验。

**test 实测结果（2026-07-29）**：未加前缀的邮箱残留 **0 条**；**188 个账号**哈希统一，且与本机计算值一致。

### 这个库的三个坑

1. **用户表叫 `user`** —— SQL 保留字，任何查询都要加双引号（`select * from "user"`）。脚本用 `quote_ident()` 处理了。
2. **`password_hash` 是 `bytea`** 不是文本 —— 写入要 `decode('<hex>','hex')`，直接塞十六进制字符串会写成字面量。脚本按 `data_type` 分支处理了。
3. **password_hash 分布在三张表**：`user`、`sign_up_data`、`sign_in_data` —— 只改 `user` 表会漏，注册/登录流程仍拿旧哈希。脚本是按列名 `%password%hash%` 全库扫的，不会漏。

> 换环境或换 `PASSWORD_SALT` 后必须重跑本脚本，否则所有账号登录失败。

## 可视化页面

1. **RDS 实例页**：<https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:>
   - 建库/同步本身在控制台看不到库列表，这里确认实例 Available、连接数曲线（Monitoring 页签）在同步期间有波动。
2. **Systems Manager → Session Manager**（上 VPC 内机器执行用）：
   - 直达：<https://us-east-1.console.aws.amazon.com/systems-manager/session-manager>
   - Start session 选中应用机（标签 `CssEnv=css-<env>`），免 SSH 密钥直接开 shell 跑本目录脚本。
3. 库级核对靠 psql：`docker run --rm -e PGPASSWORD=... postgres:16 psql -h <host> -U postgres -l` 看库列表；抽查表数/行数。

## 状态/注意

- 状态：✅ test 库（`css-test-main`/`css-test-ocr`）已于 2026-07-28 用 restore-dump-via-gw.sh 从 preprod 备份载入 `css-non-prod`，并于 **2026-07-29 用 anonymize-db.sh 完成脱敏**（统一口令 `Test1234!`）；uat/prod 库等对应节点就绪后执行（脚本本身免费）。
- 同步完成后核对目标库 `alembic_version` 是否与代码迁移链一致——**不一致勿跑 alembic upgrade**。
- 切库后同步改环境变量：`POSTGRES_DB=css-<env>-main`，`OCR_DATABASE_URL`/`OCR_ALEMBIC_DATABASE_URL` 指向 `css-<env>-ocr`。
