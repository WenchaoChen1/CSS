# deploy-env/ —— 各环境的环境变量底稿（2026-07-28 由 CSS_backend-main/deploy/env 迁出）

按用户拍板：**环境配置不放在后端代码仓库里**，统一放工作区根（与 CSS_backend-main / CSS_frontend-main 同级）。
布局固定为 `chain-serve/{CSS_backend-main,CSS_frontend-main,deploy-env}`——后端 `deploy/compose/*.yml`、
`deploy/windows/*.ps1` 与 `docs/新aws账号` 的脚本都按这个相对位置引用本目录。

```
deploy-env/
├── dev/   backend.env + frontend.env   ← 本地开发真实值【不入库】（本地dev.ps1 / compose dev.yml 直接读）
├── test/  backend.env + frontend.env   ← test 环境真实值【不入库】＝ Parameter Store 的本地底稿
├── uat/   *.example                    ← 模板（照抄填值后另存为 backend.env / frontend.env）
└── prod/  *.example                    ← 模板（prod 密钥全新生成，勿从其他环境复制）
```

## 用法

- **AWS 环境（test/uat/prod）唯一事实源是 SSM Parameter Store** `/css/<env>/{backend,frontend}.env`：
  改这里的文件只是改"底稿"，要生效必须执行 `docs/新aws账号/11-parameter-store/put-params.sh <env>` 上传，
  再重新部署（后端变量）或重新构建前端镜像（`VITE_*` 是构建期烤入）。
- **本地 dev**：`CSS_backend-main\deploy\windows\本地dev.ps1` 直接读 `dev/backend.env`，改完 `up` 即生效（无需 rebuild）。
- **dev 的 S3 已直连真实 AWS S3**：桶 `css-dev-582797602427`（us-east-1），密钥属专用 IAM 用户
  `css-app-dev`（内联策略只授权本桶）——本地开发也直传真实桶，不再使用 `localhost:9000` 的 MinIO。
- 耦合键约束：`API_KEY == VITE_X_API_KEY`、`CATALOG_OCR_API_KEY == OCR_API_KEY`，改一处必须同步另一处。
- RDS master 密码轮换（Secrets Manager 托管，7 天轮换——实测纠正）后：更新 `POSTGRES_PASSWORD` + 两个 `OCR_*_URL` 内嵌密码，重新 put-params。

## 红线

- 真实 `*.env` 永不提交（工作区 .gitignore 已忽略，仅放行 `*.example`）；本目录也不出现在任何代码仓库。
- 三环境密钥互不复用（AWS key、API_KEY、SALT 全部按环境独立）。
