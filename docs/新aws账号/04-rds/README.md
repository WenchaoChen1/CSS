# 04-rds —— 创建 RDS PostgreSQL 实例 💰

> ⚠️ **2026-07-30 起本目录创建类脚本已废弃**：实例层已由 css-terraform 接管（css-non-prod/database）：create/resize/delete-rds.sh 废弃；库级操作（05-数据同步）不变。
> 资源变更一律走 css-terraform 仓库（规范见其 CLAUDE.md）。

创建两个 RDS PostgreSQL 16 实例（各自 VPC 的私有子网，不可公网访问，主密码由 Secrets Manager 托管）：非生产 `css-non-prod`（t4g.micro，✅ 已建）、生产 `css-prod`（t4g.medium，Multi-AZ + 备份 7 天 + 删除保护，等 Paid plan）。

## 怎么用

```bash
cd docs/新aws账号/04-rds
./create-rds.sh nonprod   # css-non-prod：db.t4g.micro，备份 1 天，无删除保护（✅ 已执行）
./create-rds.sh prod      # css-prod：db.t4g.medium，Multi-AZ，备份 7 天，删除保护
```

- 前置：对应组的 VPC 已建好（`../01-vpc/`）。脚本按 Name 标签查私有子网与 `css-*-rds-sg` 安全组（仅显式校验 VPC 存在；子网/SG 缺失时由后续 AWS API 调用报错）。
- 规格：PG16（脚本运行时自动取最新 16.x 小版本，与现有 16.14 同大版本），gp3 20GB（自动扩到 100GB），存储加密，`--no-publicly-accessible`。
- 主用户 postgres 的密码走 `--manage-master-user-password`，即 Secrets Manager 托管，不落地任何文件。
- 建完约 10-15 分钟可用；就绪后到 `../05-数据同步/create-databases.sh` 建业务库。

## 可视化页面

1. **RDS 控制台**（新账号 582797602427 / us-east-1）：
   - 直达：<https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:>
   - 入口路径：控制台 → RDS → Databases
   - 看什么：实例 `css-non-prod` / `css-prod` 状态变为 **Available**；点进实例 → **Configuration** 页签核对实例类型、Multi-AZ、加密、Publicly accessible=No、子网组 `css-*-db-subnets`。
2. **Secrets Manager**：
   - 直达：<https://us-east-1.console.aws.amazon.com/secretsmanager/listsecrets?region=us-east-1>
   - 看什么：`rds!` 开头的托管 secret（RDS 主密码），点 Retrieve secret value 可查看/复制密码（勿写入任何文档）。

## 状态/注意

- ✅ 非生产 `css-non-prod` 已建成（2026-07-28，新 VPC vpc-014be109b904d6a07；旧默认 VPC 的同名实例已删）：endpoint `css-non-prod.cw9qimi6uo6c.us-east-1.rds.amazonaws.com`，PG16.14，master 用户 postgres，库 `css-test-main`/`css-test-ocr` 已从 preprod 备份载入（见 05-数据同步）。
- 💰 计费资源：非生产约 $15/月、生产约 $120/月；`css-prod` 实例仍被 Free plan 拦截，**等升级 Paid plan 后执行**。
- 实例在私有子网，本机连不上；建库/同步需在 VPC 内机器上执行或经网关机（见 05-数据同步）。
- ⚠️ 数据库版本：导数据前核对源/目标 PG **大版本**（本实例 PG16），pg_dump/pg_restore 客户端版本不得低于服务端大版本；跨大版本恢复前先在测试库演练。
