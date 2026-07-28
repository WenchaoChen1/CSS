# 05-数据同步 —— RDS 建库 + 库到库数据同步 + 本地备份恢复

三个脚本：`create-databases.sh` 在 RDS 实例上按规范建各环境业务库（ocr 库自动加 pgvector）；`sync-db.sh` 用 pg_dump→pg_restore 流式把源库数据同步到目标库（这两个需在 VPC 内执行，PG 客户端经 `docker run postgres:16` 提供）；`restore-dump-via-gw.sh` 在**本机**执行，把本地 pg_dump 备份经 S3+SSM 由网关机恢复进私网 RDS（无需上机）。

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

- 前置：网关机已由 `06-ec2/create-gateway.sh` 建成并挂 `css-gw-<组>` profile（SSM + 读 css-dbsync 桶 + 读 `rds!` secret）——nonprod=css-nonprod-gw ✅；prod 用 css-prod-bastion。
- 目标是 prod 时脚本要求输入 `prod` 二次确认（覆盖恢复生产库）。
- 同样遵守上面的 PG 版本对应注意（脚本在网关机装的是 psql16，匹配新实例 PG16）。

## 可视化页面

1. **RDS 实例页**：<https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:>
   - 建库/同步本身在控制台看不到库列表，这里确认实例 Available、连接数曲线（Monitoring 页签）在同步期间有波动。
2. **Systems Manager → Session Manager**（上 VPC 内机器执行用）：
   - 直达：<https://us-east-1.console.aws.amazon.com/systems-manager/session-manager>
   - Start session 选中应用机（标签 `CssEnv=css-<env>`），免 SSH 密钥直接开 shell 跑本目录脚本。
3. 库级核对靠 psql：`docker run --rm -e PGPASSWORD=... postgres:16 psql -h <host> -U postgres -l` 看库列表；抽查表数/行数。

## 状态/注意

- 状态：✅ test 库（`css-test-main`/`css-test-ocr`）已于 2026-07-28 用 restore-dump-via-gw.sh 从 preprod 备份载入 `css-non-prod`；uat/prod 库等对应节点就绪后执行（脚本本身免费）。
- 同步完成后核对目标库 `alembic_version` 是否与代码迁移链一致——**不一致勿跑 alembic upgrade**。
- 切库后同步改环境变量：`POSTGRES_DB=css-<env>-main`，`OCR_DATABASE_URL`/`OCR_ALEMBIC_DATABASE_URL` 指向 `css-<env>-ocr`。
