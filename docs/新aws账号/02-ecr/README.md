# 02-ecr —— ECR 镜像仓库创建（每环境独立，21 个）

一条命令按环境建齐 ECR 私有仓库：**每环境独立前缀** `<env>/css-xxx`，3 环境 × 7 仓库 = **21 个**；全部开启推送扫描（scanOnPush），并挂 lifecycle 策略——每仓库只保留最近 5 个镜像。幂等可重复执行。

## 怎么用

```bash
cd docs/新aws账号/02-ecr
./create-ecr.sh          # 无参数 = all，三环境 21 个仓库一次建齐
./create-ecr.sh test     # 只建/补齐单个环境的 7 个
```

每个环境的 7 个仓库（`<env>` = test / uat / prod）：

```
<env>/css-backend/app          <env>/css-backend/nginx
<env>/css-backend/sms-sender   <env>/css-backend/email-sender
<env>/css-backend/ai-assistant <env>/css-backend/catalog-ocr
<env>/css-frontend/app
```

## tag 规范（2026-07-28 拍板）

- **CI 推送**：不可变版本号 `<env>-vN`（N=GitHub Actions run 序号，每次发布自增，如 `test-v12`）——**回滚依据**；同时更新浮动 `<env>` tag（compose 默认引用，总是骑在最新版本上）。
- **手动推送**（`03-推送镜像/push-ecr.sh`）：缺省 `<env>-manual-<sha7>`，与 CI 的版本序列分开，不会混淆。
- lifecycle 按 push 时间每仓库保留最近 5 个镜像；浮动 `<env>` tag 指向最新镜像，不会被误删。多推会挤掉旧版本，留意回滚窗口。

## 为什么没有 db / pgadmin 仓库

- **数据库走 RDS**（`04-rds/`），AWS 环境的 compose 栈里没有 Postgres 容器，自然不需要 db 镜像；
- **pgadmin 只在本地 dev 用**，直接拉 Docker Hub 官方镜像，不进 ECR。

## 历史：2026-07-28 全量删除重建

原先是三环境共用的无前缀仓库（`css-backend/*` 含 `css-backend/db` 等），当日**全部删除**并按现行每环境独立规范重建。删除操作按用户指示直接 CLI 执行、**不留脚本**——本目录只有 `create-ecr.sh` 一个脚本。

- 已存在的仓库会复用，但 lifecycle 策略每次都会重新 put（覆盖式），改保留数直接改脚本重跑即可。

## 可视化页面

**ECR 控制台**（新账号 582797602427 / us-east-1）：

- 直达：<https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1>
- 入口路径：控制台 → Elastic Container Registry → Private registry → Repositories

在页面上看什么：

1. 仓库列表应有 **21 个** `test/…`、`uat/…`、`prod/…` 前缀仓库（搜索框按前缀过滤），Scan on push 列为 Enabled；**不应存在**无前缀旧仓库或任何 `*/db`、`*/pgadmin`。
2. 点进某个仓库 → **Images** 页签：看 tag 列表——CI 的 `<env>-vN` 不可变版本 + `<env>` 浮动 tag（指向同一 digest），手动推送则是 `<env>-manual-<sha7>`。
3. 仓库内 → **Lifecycle policy** 页签：确认规则 "keep last 5 images"（imageCountMoreThan 5 → expire）。

## 状态/注意

- ✅ 已重建（2026-07-28）：21 个仓库全部就绪（scanOnPush + lifecycle 保留 5）。
- 建仓库本身免费，费用只按镜像存储量计；lifecycle 保留 5 即为控存储成本。
- 推镜像主链路是 CI（`08-github-actions推镜像/`）；本机手动备用工具是 `03-推送镜像/push-ecr.sh`。
