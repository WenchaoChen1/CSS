# 11-parameter-store —— 环境配置灌入 SSM Parameter Store

把工作区根 `deploy-env/<env>/{backend,frontend}.env`（2026-07-28 由 `CSS_backend-main/deploy/env` 迁出，与两个代码仓库同级）上传为 `/css/<env>/{backend,frontend}.env`（SecureString）。Parameter Store 是运行时/构建期配置的**唯一事实源**：EC2 部署时自动渲染 backend.env，CI 构建前端时拉取 frontend.env。

## 脚本清单

### `put-params.sh` — 把工作区 `deploy-env/<env>/{backend,frontend}.env` 整份灌入 SSM Parameter Store（`/css/<env>/backend.env` 为 SecureString Advanced 层，`/css/<env>/frontend.env` 为 SecureString Standard 层），并回读校验 backend 长度

```bash
./put-params.sh <test|uat|prod>                       # 唯一参数：目标环境名，只接受这三个值
bash docs/新aws账号/11-parameter-store/put-params.sh test   # 典型：灌入 test 环境两份 env
```

前置：本地底稿 `deploy-env/<env>/{backend,frontend}.env` 已填好（uat/prod 以同目录 `*.example` 为底稿；密钥勿跨环境复制），缺任一文件脚本即退出。
注意：Windows git-bash 下脚本已自行处理中文路径/编码与 MSYS 路径转换问题；灌入后后端变量重跑 deploy job 生效，前端 `VITE_*` 需重新构建镜像。

改单个变量：直接在控制台改参数值后重跑对应 deploy job（后端），或改本地底稿重跑本脚本（整份覆盖）。⚠️ 耦合键成对改：`API_KEY`==`VITE_X_API_KEY`、`CATALOG_OCR_API_KEY`==`OCR_API_KEY`；`PASSWORD_SALT` 迁移必须原样搬运。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 参数列表/编辑/历史版本 | Systems Manager → **Parameter Store**：`https://us-east-1.console.aws.amazon.com/systems-manager/parameters?region=us-east-1`（点参数 → Edit 改值 → History 页签可回看每次覆盖） |

## 状态 / 注意

- test ✅ 已灌入（2026-07-28，含每环境独立 ECR 前缀 `test/css-backend` 等）；uat/prod 待环境建成后灌入；
- backend.env 用 **Advanced 层**（约 4.4KB 超过 Standard 4KB 上限，$0.05/参数/月）；
- 读取权限按环境隔离：`css-ec2-<env>`/`css-deploy-<env>` 只能读 `/css/<env>/*`。
