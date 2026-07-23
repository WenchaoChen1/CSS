# 数据迁移工具（dev 旧组织 → larry 新组织）

把 **dev 旧组织**（AWS 账号 `021213872872`，eu-central-1，全容器无 RDS）的数据库、docker 配置、S3 文件拉到本地，为迁移到 **larry 新组织**（`582797602427`，us-east-1）做准备。

> 现状：只有 **preprod**（3.74.51.100）的 SSH 权限。dev / stage（审计里的 3.124.149.172 / 52.28.87.199）SSH 未开通——配好服务器授权后，同样的脚本加 `-Source dev|stage` 即可用。

## 一次性准备

1. 复制 `源环境.env.example` → `源环境.env`，确认 preprod 的 HOST/USER/KEY（私钥 = `~/.ssh/wenchao`，带 passphrase）。
2. 拉 S3 需要 dev 账号凭证：`aws configure --profile css-src`（填 dev 账号 `021213872872` 的 AK/SK，region eu-central-1）。
   - dev 账号的 IAM key 见审计《05》轮换清单（`AKIA…GQG7J65` 那把是审计临时用的，务必换成一把最小权限的只读/迁移专用 key）。
3. （可选，回推用）larry 账号凭证：`aws configure --profile css-dst`（`582797602427`，us-east-1）。

## 三个脚本

| 脚本 | 作用 | 典型用法 |
|------|------|---------|
| `拉取数据库.ps1` | SSH 上服务器,`docker exec pg_dump` 导出 DB,scp 回本地 | `.\拉取数据库.ps1`（默认 preprod,自动发现容器/库） |
| `拉取docker-env.ps1` | 采集各容器注入的环境变量 + 磁盘 `.env` 清单 | `.\拉取docker-env.ps1` |
| `拉取S3.ps1` | 统计/下载 dev 桶,可选回推到 larry 新桶 | `.\拉取S3.ps1 -SizeOnly` 先看大小 |

### 数据库
```powershell
.\拉取数据库.ps1                       # preprod,自动发现 postgres 容器与其 POSTGRES_DB,导 custom .dump
.\拉取数据库.ps1 -Database css -Container css-backend__db   # 手动指定(自动发现不对时)
.\拉取数据库.ps1 -AllDatabases          # pg_dumpall 导整实例(含角色),产物 .sql.gz
.\拉取数据库.ps1 -Source dev            # 将来 dev 服务器 SSH 开通后
```
产物在 `_data\<source>\`。恢复：`pg_restore --no-owner --no-privileges -d <库> <文件>`。

### docker env 配置
```powershell
.\拉取docker-env.ps1                    # 产物:_env\preprod\<容器>.env + _磁盘env清单.txt
```
导出的 env **含真实凭证**,只用于本地比对/迁移,勿提交(`_env\` 已被 .gitignore 排除)。

### S3 文件
```powershell
.\拉取S3.ps1 -SizeOnly                              # 先只统计各桶大小/对象数
.\拉取S3.ps1                                         # 下载 SRC_S3_BUCKETS 全部桶到 _s3\
.\拉取S3.ps1 -Bucket chain-serve-test                # 只拉单桶
.\拉取S3.ps1 -PushToDst -DstBucket css-test-storage  # 下载后回推到 larry 新桶(需先建好目的桶)
```

## 迁移完整流程建议

1. `拉取S3.ps1 -SizeOnly` 评估数据量 → `拉取数据库.ps1` + `拉取docker-env.ps1` + `拉取S3.ps1` 落地全部数据。
2. 在 larry 新组织按目标环境创建库/桶（DB 走 RDS `css-non-prod`，S3 新建桶）。
3. `pg_restore` 恢复 DB；`拉取S3.ps1 -PushToDst` 或 `aws s3 sync` 回推文件。
4. 用 `_env\` 里导出的旧配置对照，把有效值填进 `..\env\<env>\backend.env`（真实密钥迁移后建议全部轮换，见审计《05》）。

> ⚠️ 迁移产物目录 `_data\ _env\ _s3\` 与 `源环境.env` 都含敏感数据,已在根 `.gitignore` 排除,切勿提交或外传。
