# CSS(Chain Serve)工作区

餐厅 ↔ 供应商 B2B 供应链平台。本工作区从原团队接手,包含前后端代码、脚本、备份与文档。

## 目录导航

| 路径 | 说明 |
|------|------|
| `CSS_backend-main/` | 后端(FastAPI),推送到新组织 `Chain-Serve-Solutions/Chain-Service-Solutions-Backend`(=**`origin`**;老仓库 `ChainServiceSolutions/CSS_backend`=**`oldorigin`**,只 fetch);**`deploy/`=部署中枢**(CI/CD bundle+本地 dev,见其 README) |
| `CSS_frontend-main/` | 前端(React+Vite),推送到新组织 `Chain-Service-Solutions-Frontend`(remote 同上:`origin`=新组织、`oldorigin`=老仓库) |
| `docs/环境运维执行脚本/` | 新账号(582797602427)运维脚本与 CI/CD 手册(03/05/06/07/08/09/10/11/12,每个子文件夹有 README;总流程在其 README。资源**创建**类已移交 `css-terraform` 仓库) |
| `docs/老aws账号/` | 老账号(021213872872)数据迁移工具(以只读拉取为主;容器停/启需用户明确授权) |
| `docs/云服务搭建部署方案/` | 设计方案(独立服务器/Serverless/CICD v2.2) |
| `备份/` | 迁移产物:`数据库/`、`docker镜像/`、`s3/`。**含真实数据,不进 git** |
| `审计报告/` | 安全与架构审计(已脱敏) |
| `*.local.md` / `*.local` | 私有凭证/清单,`.gitignore` 已排除 |

> `部署包/`、`发布包/`、`db_compare/` 已于 2026-07-28 退役:部署包并入 `CSS_backend-main/deploy/`,其余删除。
> `docs/环境/` 已删除:环境**实况**(拓扑/成本/服务技术)看 `css-terraform/环境实况/`,**配置值**看 `docs/环境运维执行脚本/运维访问速查.local.md`。
> 目录改名(2026-07/08):`docs/新aws账号/`→`docs/环境运维执行脚本/`、`docs/生产部署/`→`docs/云服务搭建部署方案/`。

## 三件事怎么做

### 1. 本地跑起来(开发)

```powershell
cd CSS_backend-main
.\deploy\windows\本地dev.ps1 up       # 后端全栈(改代码后 rebuild;改 env 后 up)
```
前端 `npm run dev`(:3003)。详见 [本地运行指南.md](本地运行指南.md) 与 [CSS_backend-main/deploy/README.md](CSS_backend-main/deploy/README.md)。

### 2. 部署到新 AWS 账号(test/uat/prod)——CI/CD 主链路

```bash
git checkout test && git merge ops && git push origin test   # push test/uat 即构建+migrate+部署
git push origin main                                          # 只构建 prod 镜像,不部署
# 部署 prod: GitHub Actions → CICD → Run workflow(environment=prod,image_tag 留空=重建并部署)
```
⚠️ 分支归属(2026-08-22 重建后):`uat` = main + ops、`test` = main + ops + **support-demo**、prod 走 `ops`→`main`(PR)。
**没有"test→uat→main 逐级晋级"**——**绝不能从 test 合并到 uat**(test 含老团队线,会把 uat 的 alembic 头从 `b3d9f1a2c4e5` 变成 `e8f2a4b6c1d3`)。
GitHub Free 私有仓库**没有环境审批闸**,prod 的人工闸就是"手动 Run workflow"。

手册见 [docs/环境运维执行脚本/README.md](docs/环境运维执行脚本/README.md)(总流程,组件手册在其 08/09 文件夹);具体值见 `docs/环境运维执行脚本/运维访问速查.local.md`。备用手动推镜像:`docs/环境运维执行脚本/03-本地构建推送镜像/push-ecr.sh <env>`(云上构建用同目录 `remote-build-push.sh`);人工上机:`CSS_backend-main\deploy\windows\连接EC2.ps1` 或 SSM Session。

### 3. 从老 AWS 账号迁移数据(dev 旧组织三环境)

详见 [docs/老aws账号/README.md](docs/老aws账号/README.md)。三类拉取(在 `docs\老aws账号\` 下):
```powershell
.\拉取数据库.ps1     -Source preprod    # → 备份\数据库\preprod\
.\拉取docker-env.ps1 -Source preprod    # → 备份\docker镜像\preprod\
.\拉取S3.ps1         -SizeOnly           # 先看大小; 去掉 -SizeOnly 下载到 备份\s3\
```
**三台机器 SSH 均已开通**(2026-08-03 起):dev(3.124.149.172) / stage(52.28.87.199) / preprod(3.74.51.100),用 `-Source dev|stage|preprod` 指定。

> ⚠️ **2026-08-22 起老账号分批停服**:preprod 的前端/kafka/kafka-ui/rabbitmq/**两个数据库**,以及 dev 与 stage 的
> kafka/kafka-ui/rabbitmq/**两个数据库**均已停止(`docs/老aws账号/停老环境容器.sh`)。**三个环境的库现在不可读**,
> 要取数据得先回滚启库(`docker update --restart=always` + `docker start`)。数据卷与镜像原地保留。

## 提交说明

前后端两个代码文件夹**不在本工作区仓库提交**(它们各自连自己的 GitHub 仓库,提交身份=charles)。本工作区仓库(`WenchaoChen1/CSS`)只管文档、脚本、审计报告等;凭证、备份、迁移产物均被 `.gitignore` 排除。详细交接背景见 [CLAUDE.md](CLAUDE.md)。
