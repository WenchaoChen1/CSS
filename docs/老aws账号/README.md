# 迁移工具手册 · 老 AWS 账号数据拉取（dev 旧组织 → larry 新组织）

本文件夹 = **老 AWS 账号(`021213872872` / eu-central-1,全容器无 RDS)三个环境的数据拉取工具**。
把三类东西拉到本机 `备份/` 下,为迁移到 larry 新组织(`582797602427` / us-east-1)做准备:

| 类别 | 脚本 | 落地目录 |
|------|------|---------|
| 数据库备份 | `拉取数据库.ps1` | `备份\数据库\<环境>\` |
| docker .env 配置 | `拉取docker-env.ps1` | `备份\docker镜像\<环境>\` |
| S3 文件 | `拉取S3.ps1` | `备份\s3\<桶>\` |

三个环境:`preprod`(3.74.51.100,**现只有它有 SSH 权限**)、`dev`(3.124.149.172)、`stage`(52.28.87.199)。
dev/stage 待将来在对应服务器开通 SSH 后,同一脚本加 `-Source dev|stage` 即可。

---

## 一次性准备

1. 复制 `源环境.env.example` → `源环境.env`,确认各环境 HOST/USER/KEY(私钥 = `~/.ssh/wenchao`,带 passphrase)。
2. 拉 S3 需 dev 账号凭证:`aws configure --profile css-src`(dev 账号 `021213872872` 的 AK/SK,region eu-central-1)。
   - dev 账号 IAM key 见审计《05》轮换清单(`AKIA…GQG7J65` 是审计临时用的,务必换成最小权限的迁移专用 key)。
3. (可选,回推用)larry 账号凭证:`aws configure --profile css-dst`(`582797602427`,us-east-1)。

---

## 操作 1 · 数据库备份

### 脚本方式(推荐)
```powershell
.\拉取数据库.ps1                     # 默认 preprod,自动发现 postgres 容器与其 POSTGRES_DB,导 custom .dump
.\拉取数据库.ps1 -AllDatabases        # 用 pg_dumpall 导整实例(含角色),产物 .sql.gz
.\拉取数据库.ps1 -Source dev          # 将来 dev/stage SSH 开通后
```
产物在 `备份\数据库\<环境>\`。

### 手动等价命令(不用脚本时)
> preprod 实测:两个库容器 `css-backend__db`(主库 db=`postgres`)、`css-backend__ocr-db`(OCR 库 db=`ocr_catalog`),用户都是 `postgres`。
```bash
# 1) SSH 上服务器,容器内 pg_dump 到远端 /tmp(custom 格式)
ssh -i ~/.ssh/wenchao ubuntu@3.74.51.100 \
  "docker exec css-backend__db  pg_dump -U postgres -Fc postgres     > /tmp/preprod_main.dump; \
   docker exec css-backend__ocr-db pg_dump -U postgres -Fc ocr_catalog > /tmp/preprod_ocr.dump"
# 2) scp 回本地
scp -i ~/.ssh/wenchao ubuntu@3.74.51.100:/tmp/preprod_*.dump "备份/数据库/preprod/"
# 3) 恢复到新库
pg_restore --no-owner --no-privileges -d <目标库> preprod_main.dump
```

## 操作 2 · docker .env 配置

### 脚本方式
```powershell
.\拉取docker-env.ps1                   # 产物:备份\docker镜像\<环境>\<容器>.env + _磁盘env清单.txt
```
导出的 env **含真实凭证**,只用于本地比对/迁移,勿提交(`备份\` 已被 .gitignore 排除)。

### 手动等价命令
```bash
# 列出各容器注入的环境变量
ssh -i ~/.ssh/wenchao ubuntu@3.74.51.100 \
  'for c in $(docker ps --format "{{.Names}}"); do echo "### $c"; \
     docker inspect --format "{{range .Config.Env}}{{println .}}{{end}}" $c; done'
```

## 操作 3 · S3 文件

### 脚本方式
```powershell
.\拉取S3.ps1 -SizeOnly                              # 先只统计各桶大小/对象数
.\拉取S3.ps1                                         # 下载 源环境.env 的 SRC_S3_BUCKETS 全部桶到 备份\s3\
.\拉取S3.ps1 -Bucket chain-serve-test                # 只拉单桶
.\拉取S3.ps1 -PushToDst -DstBucket css-test-storage  # 下载后回推到 larry 新桶(需先建好目的桶)
```

### 手动等价命令
```bash
aws s3 ls  s3://chain-serve-test --recursive --summarize --human-readable --profile css-src --region eu-central-1  # 先看大小
aws s3 sync s3://chain-serve-test "备份/s3/chain-serve-test" --profile css-src --region eu-central-1                # 下载
aws s3 sync "备份/s3/chain-serve-test" s3://<larry新桶>       --profile css-dst --region us-east-1                  # 回推(迁移)
```

---

## 迁移完整流程建议

1. `拉取S3.ps1 -SizeOnly` 评估数据量 → 三个脚本(或上面手动命令)落地全部数据到 `备份\`。
2. 在 larry 新组织按目标环境建库/桶(DB 走新 RDS `css-non-prod`/`css-prod`,库名规范 `css-<env>-main`/`css-<env>-ocr`,见 ../环境运维执行脚本/04、05;S3 新建桶)。
3. 恢复 DB 推荐用 `../环境运维执行脚本/05-数据库运维/restore-dump-via-gw.sh <env>`(本地 dump → S3 中转桶 → 网关机 pg_restore);`拉取S3.ps1 -PushToDst` 或 `aws s3 sync` 回推文件。
4. 用 `备份\docker镜像\` 里导出的旧配置对照,把有效值填进 SSM Parameter Store `/css/<env>/backend.env`(唯一事实源;本地底稿 = 工作区根 `deploy-env\<env>\backend.env`。真实密钥迁移后建议全部轮换,见审计《05》)。

> ⚠️ 所有产物都落在根 `备份\`(数据库/docker镜像/s3),`备份\` 与 `源环境.env` 都含敏感数据,已在根 `.gitignore` 排除,切勿提交或外传。

---

## 可视化页面（老账号 021213872872 / eu-central-1）

拉取前后到老账号控制台核对源头，到本机目录核对落地产物：

1. **EC2 实例列表**（三台源服务器）：
   - 直达：<https://eu-central-1.console.aws.amazon.com/ec2/home?region=eu-central-1#Instances:>
   - 看什么：`dev`(3.124.149.172) / `preprod`(3.74.51.100) / `stage`(52.28.87.199) 三台实例的运行状态与公网 IP——拉取前确认目标机 Running、IP 与 `源环境.env` 一致。
2. **S3 桶列表**：
   - 直达：<https://console.aws.amazon.com/s3/buckets>
   - 看什么：各桶名称与对象数/大小，和 `拉取S3.ps1 -SizeOnly` 的统计对照；确认 `源环境.env` 的 `SRC_S3_BUCKETS` 没漏桶。
3. **本机落地产物目录** `C:\github-code\chain-serve\备份\`：
   - `数据库\<环境>\` —— .dump / .sql.gz 备份文件
   - `docker镜像\<环境>\` —— 各容器 .env 导出 + 磁盘 env 清单
   - `s3\<桶>\` —— 桶文件镜像
   - 拉取后核对文件大小、时间戳是否符合预期。

> ⚠️ 老账号是**只读数据迁移源**：控制台只用来查看核对，勿在其上做任何变更（启停实例、改安全组、删桶对象等一律禁止）；所有写操作都发生在新账号（582797602427）。
