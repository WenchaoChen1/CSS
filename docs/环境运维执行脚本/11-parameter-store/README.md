# 11-parameter-store —— 环境配置灌入 SSM Parameter Store

把工作区根 `deploy-env/<env>/{backend,frontend}.env`（2026-07-28 由 `CSS_backend-main/deploy/env` 迁出，与两个代码仓库同级）上传为 `/css/<env>/{backend,frontend}.env`（SecureString）。Parameter Store 是运行时/构建期配置的**唯一事实源**：EC2 部署时自动渲染 backend.env，CI 构建前端时拉取 frontend.env。

## 脚本清单

### `put-params.sh` — 把工作区 `deploy-env/<env>/{backend,frontend}.env` 整份灌入 SSM Parameter Store（backend 为 SecureString Advanced 层，frontend 为 Standard 层），内置防误覆盖

```bash
./put-params.sh <test|uat|support-ref|support-demo|support-sync|prod>                       # 有差异时逐参数确认（输入 yes 才覆盖）
./put-params.sh test -y                               # 跳过确认（备份与差异提示照常）
```

**防误覆盖机制（2026-07-31 新增，针对"控制台页面手动改过值"的场景）**——
`deploy-env/<env>/<名>.env.remote-bak` 是**基准备份**（= 上次运行本脚本时看到的远程值；单槽位，每次运行都刷新；文件被 gitignore）。每次推送前做**三方键级对比**（只列 KEY 名，不回显值）：

| 对比 | 告诉你什么 |
|---|---|
| ① 基准 vs 远程当前 | **远程自上次以来被谁改了什么**（页面/他人的手改——覆盖后将丢失的部分） |
| ② 基准 vs 本地底稿 | **你本地改了什么**（这次要推上去的修改） |
| ③ 远程 vs 本地 | 覆盖后的**净变化**（新增/删除/改值的 KEY 清单） |

| 结果 | 行为 |
|---|---|
| 远程 == 本地 | 跳过（不产生新版本），刷新基准备份 |
| 有差异 | 打印上面三组对比 → 备份远程到 `.remote-bak` → 要求输入 `yes` 确认；不确认则远程不动 |
| 远程读取失败（非"参数不存在"） | **中止**，绝不盲推 |

想**采纳**页面上的手改而不是覆盖它：对照 `.remote-bak` 把 ① 列出的改动搬进本地底稿，再重跑（两边一致即跳过）。

前置：本地底稿 `deploy-env/<env>/{backend,frontend}.env` 已填好（uat/prod 以同目录 `*.example` 为底稿；密钥勿跨环境复制），缺任一文件脚本即退出。
注意：Windows git-bash 下脚本已自行处理中文路径/编码/MSYS 路径转换（含参数值带 `⚠` 等字符时 aws.exe 的 GBK 输出崩溃，`PYTHONUTF8=1` 根治）；灌入后后端变量重跑 deploy job 生效，前端 `VITE_*` 需重新构建镜像。

改单个变量：直接在控制台改参数值后重跑对应 deploy job（后端）——下次跑本脚本会检测到差异、备份并提示你合并回底稿；或改本地底稿重跑本脚本（整份覆盖）。⚠️ 耦合键成对改：`API_KEY`==`VITE_X_API_KEY`、`CATALOG_OCR_API_KEY`==`OCR_API_KEY`；`PASSWORD_SALT` 迁移必须原样搬运。

## 可视化页面

| 看什么 | 在哪 |
|--------|------|
| 参数列表/编辑/历史版本 | Systems Manager → **Parameter Store**：`https://us-east-1.console.aws.amazon.com/systems-manager/parameters?region=us-east-1`（点参数 → Edit 改值 → History 页签可回看每次覆盖） |

## 状态 / 注意

- test ✅ 已灌入（2026-07-28，含每环境独立 ECR 前缀 `test/css-backend` 等）；uat/prod 待环境建成后灌入；
- backend.env 用 **Advanced 层**（约 4.4KB 超过 Standard 4KB 上限，$0.05/参数/月）；
- 读取权限按环境隔离：`css-ec2-<env>`/`css-deploy-<env>` 只能读 `/css/<env>/*`。
