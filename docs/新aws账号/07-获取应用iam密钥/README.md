# 07-获取应用iam密钥 —— 应用 S3 用户的 access key 发放（唯一还在这里做的 IAM 操作）

> ⚠️ **2026-07-31 起：IAM 资源本体已 100% 由 css-terraform 管理**，本目录不再创建任何用户/角色/策略。
> - OIDC provider + `css-deploy-{test,uat,prod}`（GitHub Actions 用）→ `css-terraform/css-github`；
> - `css-ec2-<env>`（实例角色）、`css-app-<env>`（应用 S3 用户+策略）→ 各环境 `iam` stack（dev 的在 `css-non-prod/dev`）；
> - 堡垒机角色 `css-gw-non-prod` / `css-gw-prod` → 两组的 `network` stack；`css-terraform` 执行角色 → `global`。
> - 权限明细、信任策略、控制台入口的**权威文档 = `css-terraform/使用说明/06-IAM与OIDC.md`**。
>
> 本目录只剩一件事：**发 access key**。红线（css-terraform CLAUDE.md §九）规定 `aws_iam_access_key`
> 永不进 Terraform（secret 会明文落 state），所以 key 的生成/查看/轮换永远走这里的脚本。

## 脚本清单

### `issue-app-s3-key.sh` — 管理 `css-app-<env>` 应用 S3 用户的 access key（查看/发放）

```bash
./issue-app-s3-key.sh <dev|test|uat|prod>            # 不带 --new-key：查看用户与现有 key 状态
./issue-app-s3-key.sh <dev|test|uat|prod> --new-key  # 生成一对 access key 并【只打印这一次】（AWS 不会再给第二次）
./issue-app-s3-key.sh dev                            # 例：查看 css-app-dev 的现有 key 状态
./issue-app-s3-key.sh test --new-key                 # 例：给 css-app-test 发一对新 key
```

前置条件：`css-app-<env>` 用户须已由 css-terraform 创建——脚本**不建用户不挂策略**（用户不存在会报错并指向对应 Terraform stack）；旧名 `07-iam/create-app-s3-user.sh`，2026-07-31 改名对齐现职能。

- 每用户最多 2 个 key（AWS 上限），轮换 = 发新 → 切配置 → 删旧（删除命令脚本会打印）。
- 发出的 key 去向：dev 写工作区 `deploy-env/dev/backend.env`（不入库，本地直接生效）；
  test/uat/prod 写 `deploy-env/<env>/backend.env` 底稿 → `../11-parameter-store/put-params.sh <env>` 推送 → 走 09 重新部署。

## 为什么 S3 访问用 IAM 用户而不是实例角色

后端代码要求显式的 `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` 环境变量（boto3 显式凭证），
拿不到实例角色的临时凭证；本地开发机（dev）更是没有实例角色可用。每个用户的内联策略
`css-app-<env>-s3` 只授权本环境的桶 `css-<env>-582797602427`（桶级 List + 对象级读写删/分段上传），跨桶一律无权。

## 当前用户与 key 状态（2026-07-31）

| 用户 | 属于 | key 状态 |
|------|------|---------|
| `css-app-dev` | css-non-prod / css-dev（本地开发直传 S3，非部署环境） | ✅ 已发（07-29），写在 `deploy-env/dev/backend.env` |
| `css-app-test` | test | ✅ 已发（07-29）且 **test 环境在用**（配置在 `/css/test/backend.env`） |
| `css-app-uat` / `css-app-prod` | uat / prod | ⏳ 未发（避免闲置长期凭证；uat/prod 首次部署前发） |
| `css-test` | 人工运维（本机 aws cli 身份，Admin 组，**非应用 key**） | 有（本机 `~/.aws/credentials`）；⚠️ 建议轮换并降级为 AssumeRole css-terraform（见 运维访问速查 §七/§九） |

## 可视化页面

- IAM Users 搜 `css-app-`：<https://console.aws.amazon.com/iam/home#/users>——四个用户各有一条内联策略
  `css-app-<env>-s3`；Security credentials 页签里目前 `css-app-dev` 与 `css-app-test` 有 access key（uat/prod 为空）。
- 角色/OIDC/信任策略的查看入口见 `css-terraform/使用说明/06-IAM与OIDC.md`。

## 历史备注

- 原 `create-iam.sh`（一次建齐 OIDC + 三环境角色）已随 Terraform 接管删除；本 README 旧版的 IAM 全量
  清单（角色/信任/权限表）已由 `使用说明/06-IAM与OIDC.md` 取代，不在此维护第二份。
- 遗留角色 `css-non-prod-ec2-role` 与 instance profile 已于 2026-07-30 删除。
- 2026-07-30 安全审计后：`css-ec2-<env>` 的 ECR 拉取已收窄到 `<env>/*`，并各加显式 Deny 防跨环境读参数。
