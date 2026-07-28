# 11-parameter-store —— 环境配置灌入 SSM Parameter Store

把工作区根 `deploy-env/<env>/{backend,frontend}.env`（2026-07-28 由 `CSS_backend-main/deploy/env` 迁出，与两个代码仓库同级）上传为 `/css/<env>/{backend,frontend}.env`（SecureString）。Parameter Store 是运行时/构建期配置的**唯一事实源**：EC2 部署时自动渲染 backend.env，CI 构建前端时拉取 frontend.env。

## 怎么用

```bash
# 前置：本地底稿已填好（uat/prod 以同目录 *.example 为底稿；密钥勿跨环境复制）
bash docs/新aws账号/11-parameter-store/put-params.sh test
```

改单个变量：直接在控制台改参数值后重跑对应 deploy job（后端），或改本地底稿重跑本脚本（整份覆盖）。⚠️ 耦合键成对改：`API_KEY`==`VITE_X_API_KEY`、`CATALOG_OCR_API_KEY`==`OCR_API_KEY`；`PASSWORD_SALT` 迁移必须原样搬运。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 参数列表/编辑/历史版本 | Systems Manager → **Parameter Store**：`https://us-east-1.console.aws.amazon.com/systems-manager/parameters?region=us-east-1`（点参数 → Edit 改值 → History 页签可回看每次覆盖） |

## 状态 / 注意

- test ✅ 已灌入（2026-07-28，含每环境独立 ECR 前缀 `test/css-backend` 等）；uat/prod 待环境建成后灌入；
- backend.env 用 **Advanced 层**（约 4.4KB 超过 Standard 4KB 上限，$0.05/参数/月）；
- 读取权限按环境隔离：`css-ec2-<env>`/`css-deploy-<env>` 只能读 `/css/<env>/*`。
