# 05-数据库运维 —— 建库 / 数据同步与恢复 / 脱敏 / 库账号与改密 / 对象 owner（原 05-数据同步）

本目录共 **10 个脚本**，覆盖 RDS 库的全生命周期运维：建库 → 灌数据（同步/恢复）→ 脱敏 → 建账号 → 改密 → 移交对象 owner。用法详见下面的脚本清单。

通用注意：

- ⚠️ 除 `restore-dump-via-gw.sh`、`restore-old-env-backup.sh` 和 `anonymize-db.sh`（在**本机**执行，经 S3/SSM 落到 AWS 内机器）外，其余脚本 **必须在 VPC 内机器上执行**（RDS 在私有子网，本机不可达）——上应用机或经网关机隧道，需 Docker；PG 客户端一律经 `docker run postgres:16` 提供，机器无需装 pg 工具。
- master 密码从 Secrets Manager 取（`rds!` 前缀 secret），命令行传参即可，勿写进文件；各库账号密码见 `运维访问速查.local.md`。
- 库名规范（2026-07-28 拍板）：`css-<env>-main` / `css-<env>-ocr`，含连字符——SQL 内脚本已用双引号处理，DSN 里可直接使用。
- ⚠️ **PG 版本对应**：导数据前核对源/目标 **大版本**（新实例 PG16.14），pg_dump/pg_restore 客户端版本**不得低于服务端大版本**；跨大版本恢复前先在测试库演练。

## 脚本清单

### `db-tunnel.sh` — 一键打开【本机 → RDS】SSH 隧道，供 Navicat/DBeaver/psql 直连（不经过应用代码）

```bash
./db-tunnel.sh <test|uat|prod> [本地端口]   # 端口缺省 5433；前台运行，Ctrl+C 关闭
./db-tunnel.sh test                        # 然后客户端连 localhost:5433
./db-tunnel.sh uat 5434                    # 同时开两条隧道时用不同端口
./db-tunnel.sh test --check                # 只探测链路是否通，不驻留
DEV_KEY=deploy-env/ssh/dev-keys/nonprod-张三.pem ./db-tunnel.sh test   # 开发者用自己的临时钥
```

RDS endpoint 由 aws cli 动态查询（实例换了也不会过期）；启动后会打印客户端要填的全部参数。
前置：本机出口 IP 在堡垒机 22 端口白名单内 + 有私钥（管理员钥见速查，开发者钥用 `../06-服务器密钥与访问/grant-dev-ssh.sh` 发）。
密码见 `../运维访问速查.local.md`；三种连接方式的完整对比见 [`../本地连接数据库.md`](../本地连接数据库.md)。

### `create-databases.sh` — 在 RDS 实例上按规范创建各环境业务库（ocr 库自动加 pgvector 扩展）

```bash
./create-databases.sh <rds主机> '<master密码>' <env...>       # env 可多个：test|uat|prod
./create-databases.sh <rds主机> '<master密码>' test uat       # 非生产实例建 test+uat 四个库
./create-databases.sh <rds主机> '<master密码>' prod           # 生产实例建 prod 两个库
```

已存在的库跳过（幂等）。建完记得同步改环境变量：`POSTGRES_DB=css-<env>-main`，`OCR_DATABASE_URL`/`OCR_ALEMBIC_DATABASE_URL` 指向 `css-<env>-ocr`。

### `sync-db.sh` — 把源库数据流式同步到目标库（pg_dump -Fc → pg_restore，无中间文件）

```bash
./sync-db.sh '<源DSN>' '<目标DSN>'
./sync-db.sh 'postgresql://postgres:PASS@old-host:5432/css_test' \
             'postgresql://postgres:PASS@new-host:5432/css-test-main'   # 例：旧库 → 新实例；也可 test → uat 作验收基线
```

- ⚠️ 带 `--clean --if-exists`，目标库同名对象会先被清掉；**生产同步前先打快照**。需在能同时连通两端的机器上执行。
- 同步后核对目标库 `alembic_version` 是否与代码迁移链一致——**不一致勿跑 alembic upgrade**。

### `restore-dump-via-gw.sh` — 在本机把本地 pg_dump 备份经 S3+SSM 由网关机恢复进私网 RDS（无需上机）

本地无法直连私有子网 RDS 时用（✅ 2026-07-28 已用它把 preprod 备份载入 test 库）。链路：

```
本地 pg_dump -Fc 备份 → S3 中转桶 css-dbsync-<账号>（私有+PAB 全开，**用时自动创建、用完清空对象**；不常驻、不入 TF）
  → SSM Run Command 在网关机上执行：装 psql16 客户端 → 从 Secrets Manager 自取 RDS 托管密码（密码不出 AWS）
  → 建库（css-<env>-main / css-<env>-ocr，ocr 自动加 pgvector）→ pg_restore → 清理（S3 dump 用完即删）
```

```bash
./restore-dump-via-gw.sh <test|uat|prod> <main库dump> <ocr库dump>
# 例（已执行）：
./restore-dump-via-gw.sh test ../../../备份/数据库/preprod/preprod_main_xxx.dump \
                              ../../../备份/数据库/preprod/preprod_ocr_xxx.dump
```

- 前置：堡垒机已由 css-terraform `network` stack 建成并挂 `css-gw-non-prod` / `css-gw-prod` profile（SSM + 读 css-dbsync 桶 + 读 `rds!` secret）——nonprod=`css-non-prod-bastion` ✅；prod 用 `css-prod-bastion` ✅。
- 目标是 prod 时脚本要求输入 `prod` 二次确认（覆盖恢复生产库）；网关机装的是 psql16，匹配新实例 PG16。

### `restore-old-env-backup.sh` — 把老账号三环境的数据库备份，恢复成非生产 RDS 上的**独立留档库**（不碰现有环境库）

```bash
./restore-old-env-backup.sh <dev|stage|preprod|all> [YYYYMMDD]
./restore-old-env-backup.sh --list        # 只列出 RDS 上现有的库，不做任何改动
```

**与上面 `restore-dump-via-gw.sh` 的区别（为什么不复用它）**：

| | `restore-dump-via-gw.sh` | `restore-old-env-backup.sh` |
|---|---|---|
| 用途 | **环境投产**：把数据灌进正在用的环境库 | **留档快照**：把老环境的某天状态存起来备查 |
| 目标库 | 硬编码 `css-<env>-main`/`css-<env>-ocr` | `css-old-<源环境>-main-备份_YYYYMMDD`（带日期，每次新库） |
| 覆盖行为 | 带 `--clean --if-exists`，**清空覆盖** | **不带 --clean**；库已存在则**跳过**，绝不替人删数据 |
| 接应用 | 是（backend.env 指向它） | 否，不接任何应用 |

链路与 `restore-dump-via-gw.sh` 相同（本地 dump → S3 中转桶 → SSM 在网关机上 pg_restore）。
dump 来自 `../../老aws账号/拉取三环境.sh`，日期后缀缺省从 dump 文件名解析。

**两个 Windows 侧的坑（脚本已处理，改动时勿退回）**：

1. dump 路径在 `备份/数据库/` 下**含中文**，而 `aws.exe` 是 Windows 原生程序——git-bash 把含中文的路径
   当参数传给它时会按 ANSI 编码破坏（实测报 `/c/github-code/chain-serve//ݿ/dev/... does not exist`）。
   脚本改用 **stdin 重定向**（`aws s3 cp - s3://... < "$DUMP"`），由 bash 自己开文件，绕开参数传递。
2. 库名里的中文**在链路上是完好的**（已用 hex 实证：远端与库内均为正确 UTF-8 `e5a487e4bbbd`=备份）；
   终端里看到的乱码只是 Windows 控制台按 GBK 解码 aws CLI 输出所致，**不是库名坏了**。核验请用
   `select encode(convert_to(datname,'UTF8'),'hex') ...`，别信终端回显。

**已执行（2026-08-03）**：六个库全部恢复成功，且源库与备份库的**全表行数指纹逐字节一致**：

| 源环境 | 表数 | 总行数 | 指纹 md5 | alembic |
|---|---|---|---|---|
| dev | 154 | 237,096 | `6e6bb1f095fea40efff0165e8a7c589a` | `e8f2a4b6c1d3` |
| stage | 154 | 262,003 | `6b7f6e0928627f35169e42322e2aac3e` | `e8f2a4b6c1d3` |
| preprod | 146 | 88,254 | `b526e41746528bade32ad97db0135b7b` | `e1f2a3b4c5d6` |

> ⚠️ 这六个库**含老环境的真实 PII，未脱敏**。它们不接应用、仅供查数据/比对 schema；
> 长期留存请考虑 `mask-residual-pii.sh`，或用完即 `DROP DATABASE "css-old-<env>-main-备份_<日期>"`。

### `anonymize-db.sh` — 非生产库脱敏：邮箱/手机加扰 + 口令哈希统一（导入真实数据后**必须**执行一次）

从 preprod/生产导入的库里全是真人邮箱、手机号和真实口令哈希。**非生产环境不允许留真实个人数据**，恢复完必须跑一次脱敏。`prod` 参数脚本会**直接拒绝执行**。

```bash
./anonymize-db.sh <test|uat> [口令]     # 口令缺省 Test1234!
# 已执行（2026-07-29）：
./anonymize-db.sh test
```

做了三件事（动态遍历 `information_schema` 找列，只认 `text`/`varchar`/`char`，排除列名含 `type` 的枚举字段）：

| # | 对象 | 处理 | 效果 |
|---|------|------|------|
| 1 | 所有 **email** 类文本列 | 值**前面加 `1`** → `1foo@bar.com` | 发不出去，也认不出是谁；已加过前缀的跳过（幂等） |
| 2 | 所有 **phone** 类文本列 | 值**后面加 `1`**（幂等：已以 1 结尾的跳过） | 打不通。⚠️ 已知边界：首轮对全新数据，**真实尾号为 1 的号码（≈1/10）会被跳过保留原值**（值形态无法区分"已脱敏"；email 同理但 1 开头的真实邮箱罕见）。**已由 mask-residual-pii.sh 补齐**（见下） |
| 3 | 所有 **password_hash** 列 | 统一为口令 **`Test1234!`** 的哈希 | 所有账号一个口令，方便测试 |

哈希算法取自目标环境的 `deploy-env/<env>/backend.env`：`pbkdf2_hmac(PASSWORD_HASH_ALGORITHM, 口令, PASSWORD_SALT, PASSWORD_HASH_ITERATIONS)`
= sha256 + env 里的 `PASSWORD_SALT` + **10 万次迭代**。**盐必须与运行环境一致**，否则改完仍然登录不上——历史踩过这个坑
（导入的用户用的是原团队的 salt，而 env 里是随机 salt，结果登录全挂）。密码明文只在本机参与计算，不进 AWS 日志。

**执行链路**：本机算哈希 → SSM Run Command 发到该环境应用机（按标签 `Environment=css-<env>` 定位，机器在 VPC 内能连 RDS）
→ 机器上读 `/opt/css-cicd/env/<env>/backend.env` 取库连接 → `docker run postgres:16 psql` 生成并在**单事务**里执行全部 UPDATE → 前后各抽样校验。

**test 实测结果（2026-07-29）**：未加前缀的邮箱残留 **0 条**；**188 个账号**哈希统一，且与本机计算值一致。

> 换环境或换 `PASSWORD_SALT` 后必须重跑本脚本，否则所有账号登录失败。

#### 这个库的三个坑

1. **用户表叫 `user`** —— SQL 保留字，任何查询都要加双引号（`select * from "user"`）。脚本用 `quote_ident()` 处理了。
2. **`password_hash` 是 `bytea`** 不是文本 —— 写入要 `decode('<hex>','hex')`，直接塞十六进制字符串会写成字面量。脚本按 `data_type` 分支处理了。
3. **password_hash 分布在三张表**：`user`、`sign_up_data`、`sign_in_data` —— 只改 `user` 表会漏，注册/登录流程仍拿旧哈希。脚本是按列名 `%password%hash%` 全库扫的，不会漏。

### `mask-residual-pii.sh` — 补脱敏：把 anonymize 漏掉/掩盖不住的真实个人数据换成确定性合成值，并写脱敏标记表

```bash
./mask-residual-pii.sh <test|uat>          # 默认 residual 模式：只处理【歧义/未脱敏】的行
./mask-residual-pii.sh test --all          # 彻底模式：全部 email/phone 换合成值（⚠️ 测试账号登录名会变）
```

**为什么需要它**（2026-08-03 实查发现，anonymize-db.sh 的两个固有缺陷）：

| 缺陷 | 实证 |
|---|---|
| ① "加前缀 1" **只断可达性、不断身份** | `1jiahuang659@gmail.com`、`1239pelico.neftali@gmail.com` —— 真人身份一眼可读，README 原先写的"认不出是谁"是错的 |
| ② 用"值形态"判断是否已脱敏 → 原本就以 1 开头的真实邮箱**永远不会被脱敏**，事后也无法与已脱敏区分 | test/uat 各命中 4 个这样的歧义值（含上面那个带真人姓名的） |

**它怎么解决**：换成**确定性合成值**（同一原值恒得同一结果，可重复、不破唯一约束、零真实身份）——
`email → 1m<md5前10>@example.invalid`（保持 1 开头兼容既有校验）、`phone → 900+9位`；
并建 **`_css_pii_masked` 标记表**，从此"脱没脱过"看标记，不再猜值形态。

**执行链路**：在**堡垒机**上跑（master 密码由机器自己从 Secrets Manager 现取，不进 SSM 命令文本与日志），
远端脚本用 base64 传输（规避 heredoc 转义坑）；不依赖应用机是否部署过——uat 没部署也能跑。

**已执行（2026-08-03）**：test ✅ 4 行、uat ✅ 4 行，均已写标记表、复跑零残留；OCR 库实查无 email/phone 列，无需处理。

> ⚠️ **residual 模式后库里仍是"1+真实身份"的形态**（那是 anonymize 的既有口径，非本脚本引入）。
> 要做到真正"认不出是谁"，跑 `--all`——代价是全部测试账号登录名改变，需同步通知使用者。**这一步待拍板**。

### `create-db-accounts.sh` — 在 RDS 上创建库级隔离的登录角色（低权应用账号 + dev + ops 超级账号）

```bash
./create-db-accounts.sh <rds主机> <master密码> [test|uat|both]   # 缺省 both
./create-db-accounts.sh <rds主机> <master密码> both              # 一次建齐 test+uat 全套账号
```

角色与授权：

| 角色 | 权限 |
|------|------|
| `css_app_test` | 仅 `css-test-main` / `css-test-ocr` 读写（应用/运维） |
| `css_app_uat` | 仅 `css-uat-main` / `css-uat-ocr` 读写 |
| `css_dev` | 可建新库（CREATEDB）；test+uat 四库读写改数据；不能删 `css-*` 存量库（非 owner）——但 PG 语义下能删【自己新建的】库 |
| `css_ops` | `rds_superuser`（全库超级权限，人用；通过堡垒机隧道连）。**对今后新建的库自动有权限**——靠 rds_superuser 成员继承，不需要逐库授权；脚本内置断言，机制失效会立刻报错（2026-08-03 实测确认：新建库 + REVOKE PUBLIC + 零显式授权 → css_ops 仍可连） |

- 隔离手段：每个库 `REVOKE CONNECT FROM PUBLIC` 后只 GRANT 给授权角色；master(postgres) 是 superuser 不受影响。
- **重跑本脚本即全员轮换密码**（ALTER ROLE 重设并打印新值）；新密码立刻抄进 `运维访问速查.local.md` 并同步应用配置。`css_app_prod` 待 prod RDS 建成后另跑。

### `change-db-password.sh` — 单独修改某一个数据库账号的密码（不动其他账号、不动授权）

```bash
./change-db-password.sh <rds主机> <master密码> <账号名>              # 随机生成 20 位字母数字并打印
./change-db-password.sh <rds主机> <master密码> <账号名> '<新密码>'    # 用指定密码（建议纯字母数字，免 URL 转义）
```

- 适用账号：`css_app_test` / `css_app_uat` / `css_app_prod` / `css_dev` / `css_ops`；**master(postgres) 的密码由 Secrets Manager 托管**，改它用 `aws secretsmanager rotate-secret`，不用本脚本。
- 改完记得：① 抄进 `运维访问速查.local.md`；② 若该账号被应用使用 → 改 `deploy-env/<env>/backend.env` 相应 3 处 → `put-params.sh <env>` → `deploy-env.sh <env> core` 重启生效。

### `reown-db-objects.sh` — 把库内 public schema 存量对象的 owner 从 master(postgres) 移交给 css_app_&lt;env&gt;

```bash
./reown-db-objects.sh <rds主机> <master密码> <test|uat|prod>
./reown-db-objects.sh <rds主机> <master密码> test    # 移交 css-test-main / css-test-ocr 两库的对象 owner
```

为什么需要：库是用 `pg_restore --no-owner -U postgres` 恢复的，所有表 owner=postgres；`GRANT ALL` 只给 DML，而 `ALTER TABLE` / `DROP TABLE` / `CREATE INDEX` **只认 owner 不认 GRANT**——不移交所有权，应用切到 `css_app_<env>` 后 alembic 迁移会报 "must be owner of table xxx"。脚本逐类移交表/序列/视图/物化视图/类型&domain/函数（**不用** `REASSIGN OWNED BY`，那会连其它库的 shared object 一起改），并保留 `css_dev` 对新 owner 未来新建对象的读写。

- ⚠️ 每次跑 `restore-dump-via-gw.sh` / `sync-db.sh`（都以 postgres 身份 `--no-owner` 恢复）之后，owner 会被打回 postgres，**必须重跑本脚本**。
- 跑完下一步：把 `deploy-env/<env>/backend.env` 的 `POSTGRES_USER`/`POSTGRES_PASSWORD` 与两个 `OCR_*_URL` 改成该角色，再 `put-params.sh <env>` + `deploy-env.sh <env> migrate + up`。

## 可视化页面

1. **RDS 实例页**：<https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:>
   - 建库/同步本身在控制台看不到库列表，这里确认实例 Available、连接数曲线（Monitoring 页签）在同步期间有波动。
2. **Systems Manager → Session Manager**（上 VPC 内机器执行用）：
   - 直达：<https://us-east-1.console.aws.amazon.com/systems-manager/session-manager>
   - Start session 选中应用机（标签 `Environment=css-<env>`），免 SSH 密钥直接开 shell 跑本目录脚本。
3. 库级核对靠 psql：`docker run --rm -e PGPASSWORD=... postgres:16 psql -h <host> -U postgres -l` 看库列表；抽查表数/行数。

## 状态/注意

- 状态：✅ test 库（`css-test-main`/`css-test-ocr`）已于 2026-07-28 用 restore-dump-via-gw.sh 从 preprod 备份载入 `css-non-prod`，并于 **2026-07-29 用 anonymize-db.sh 完成脱敏**（统一口令 `Test1234!`）；uat/prod 库等对应节点就绪后执行（脚本本身免费）。
- 同步完成后核对目标库 `alembic_version` 是否与代码迁移链一致——**不一致勿跑 alembic upgrade**。
- 切库后同步改环境变量：`POSTGRES_DB=css-<env>-main`，`OCR_DATABASE_URL`/`OCR_ALEMBIC_DATABASE_URL` 指向 `css-<env>-ocr`。
