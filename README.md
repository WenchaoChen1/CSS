# CSS(Chain Serve)工作区

餐厅 ↔ 供应商 B2B 供应链平台。本工作区从原团队接手,包含前后端代码、脚本、备份与文档。

## 目录导航

| 路径 | 说明 |
|------|------|
| `CSS_backend-main/` | 后端(FastAPI),推送到新组织 `Chain-Serve-Solutions/Chain-Service-Solutions-Backend`(fetch 老仓库=origin);**`deploy/`=部署中枢**(CI/CD bundle+本地 dev,见其 README) |
| `CSS_frontend-main/` | 前端(React+Vite),推送到新组织 `Chain-Service-Solutions-Frontend` |
| `docs/新aws账号/` | 新账号(582797602427)脚本与 CI/CD 手册(01-vpc ~ 11-parameter-store,每个子文件夹有 README;总流程在其 README) |
| `docs/老aws账号/` | 老账号(021213872872)数据迁移工具(只读拉取) |
| `docs/环境/` | 三环境权威文档(拓扑/群组/成本/配置速查) |
| `docs/生产部署/` | 设计方案(独立服务器/Serverless/CICD v2.2) |
| `备份/` | 迁移产物:`数据库/`、`docker镜像/`、`s3/`。**含真实数据,不进 git** |
| `审计报告/` | 安全与架构审计(已脱敏) |
| `*.local.md` / `*.local` | 私有凭证/清单,`.gitignore` 已排除 |

> `部署包/`、`发布包/`、`db_compare/` 已于 2026-07-28 退役:部署包并入 `CSS_backend-main/deploy/`,其余删除。

## 三件事怎么做

### 1. 本地跑起来(开发)

```powershell
cd CSS_backend-main
.\deploy\windows\本地dev.ps1 up       # 后端全栈(改代码后 rebuild;改 env 后 up)
```
前端 `npm run dev`(:3003)。详见 [本地运行指南.md](本地运行指南.md) 与 [CSS_backend-main/deploy/README.md](CSS_backend-main/deploy/README.md)。

### 2. 部署到新 AWS 账号(test/uat/prod)——CI/CD 主链路

```bash
git push neworg test        # push 即构建+部署 test;uat/main 同理(prod 需 GitHub 页面审批)
```
手册见 [docs/新aws账号/README.md](docs/新aws账号/README.md)(总流程,组件手册在其 08/09 文件夹);具体值见 [docs/环境/配置速查.md](docs/环境/配置速查.md)。备用手动推镜像:`docs/新aws账号/03-推送镜像/push-ecr.sh <env>`;人工上机:`CSS_backend-main\deploy\windows\连接EC2.ps1` 或 SSM Session。

### 3. 从老 AWS 账号迁移数据(dev 旧组织三环境)

详见 [docs/老aws账号/README.md](docs/老aws账号/README.md)。三类拉取(在 `docs\老aws账号\` 下):
```powershell
.\拉取数据库.ps1     -Source preprod    # → 备份\数据库\preprod\
.\拉取docker-env.ps1 -Source preprod    # → 备份\docker镜像\preprod\
.\拉取S3.ps1         -SizeOnly           # 先看大小; 去掉 -SizeOnly 下载到 备份\s3\
```
现仅 preprod(3.74.51.100)有 SSH 权限;dev/stage 待开通后加 `-Source dev|stage`。

## 提交说明

前后端两个代码文件夹**不在本工作区仓库提交**(它们各自连自己的 GitHub 仓库,提交身份=charles)。本工作区仓库(`WenchaoChen1/CSS`)只管文档、脚本、审计报告等;凭证、备份、迁移产物均被 `.gitignore` 排除。详细交接背景见 [CLAUDE.md](CLAUDE.md)。
