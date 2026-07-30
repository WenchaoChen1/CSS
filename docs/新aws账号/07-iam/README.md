# 07-iam —— CI/CD 与运行时 IAM（OIDC + 三环境隔离角色）

一条命令建齐 CI/CD 与运行所需的全部 IAM（零成本）：GitHub OIDC provider + 每环境一套完全隔离的三件套——部署角色 `css-deploy-<env>`（GitHub Actions 假扮）、EC2 实例角色 `css-ec2-<env>`、应用 S3 用户 `css-app-<env>`（由 `create-app-s3-user.sh` 单独维护，缺省不生成 key）。幂等：存在即复用，策略覆盖式刷新。

## 怎么用

```bash
cd docs/新aws账号/07-iam
./create-iam.sh    # 无参数，一次建齐 OIDC provider + test/uat/prod 三套角色
```

- 部署角色的 OIDC 信任限定到新组织 `Chain-Serve-Solutions` 两个仓库（Backend/Frontend）的对应分支 push + GitHub environment job，分支↔环境一一对应。
  📌 **2026-07-29 起：GitHub environment 名与分支名一律相同——`test` / `uat` / `main`**（生产环境的 environment 就叫 `main`，不再叫 `production`）。信任策略里写的 `environment:<名>` 必须与 workflow `environment:` 用的名字逐字相同，否则 AccessDenied。
  ⚠️ 本组织 GitHub 签发的 sub 是**带唯一 ID 的新格式**（如 `repo:Chain-Serve-Solutions@309824177/...@1314034286:ref:...`），信任策略里新旧两种格式各写了一份（`@*` 只通配数字 ID）——精简时别删掉 `@*` 那组，否则 CI 换凭证直接 AccessDenied。
- 凭证隔离原则：任何 key/角色不跨环境复用，权限只够本环境（`docs/生产部署/03-CICD-GitHub-Actions.md` §4.5）。
- Windows git-bash 下脚本已处理 `file://` 临时路径的 MSYS→Windows 转换，直接跑即可。

## IAM 全量清单：每个账号的用处与权限（2026-07-28 实查）

### 角色（8 个 = 7 个在用的 `css-*` + 1 个遗留）

在用的 7 个：`css-deploy-{test,uat,prod}` + `css-ec2-{test,uat,prod}` + `css-gw-non-prod`；
遗留的 1 个是 `css-non-prod-ec2-role`（已无使用者，可删）。生产网关的 `css-gw-prod` 要等 `create-gateway.sh prod` 执行后才会出现。

| 角色 | 用处 | 谁能用它（信任） | 具体权限 |
|------|------|------------------|----------|
| `css-deploy-test` | **test 环境 CI/CD**：GitHub Actions 推镜像（现阶段）+ 将来恢复自动部署 | GitHub OIDC：两仓库 `test` 分支 push / `test` environment | ① ECR 登录 + push/pull **仅 `test/*` 仓库**；② `ssm:SendCommand` **仅打了 `CssEnv=css-test` 标签的 EC2**（部署用）；③ 读写参数 **仅 `/css/test/*`**；④ `ec2:DescribeInstances`（找目标机） |
| `css-deploy-uat` | uat 环境 CI/CD（同上） | 两仓库 `uat` 分支 / `uat` environment | 同上（uat 前缀）＋ **RDS 快照**（`rds:CreateDBSnapshot` 等，migrate 前自动快照用） |
| `css-deploy-prod` | prod 环境 CI/CD（同上） | 两仓库 `main` 分支 / `main` environment（2026-07-29 由 `production` 改名为 `main`，与分支同名） | 同上（prod 前缀）＋ RDS 快照 |
| `css-ec2-test` | **test 应用机的实例角色**（机器自己对 AWS 的权限） | EC2 服务（挂到实例） | ① `AmazonSSMManagedInstanceCore`（被 SSM 管理/收部署命令）；② `AmazonEC2ContainerRegistryReadOnly`（拉镜像）；③ **只读** `/css/test/*` 参数（deploy.sh 渲染 env 用） |
| `css-ec2-uat` | uat 应用机实例角色 | 同上 | 同上（uat 前缀） |
| `css-ec2-prod` | prod 应用机实例角色 | 同上 | 同上（prod 前缀） |
| `css-gw-non-prod` | **非生产网关机（css-non-prod-gw）实例角色**：运维通道，2026-07-28 由 06-ec2/create-gateway.sh 创建，**2026-07-29 由 `css-gw-nonprod` 改名重建**（IAM 角色名同样不可改，只能新建 → 换绑 instance profile → 删旧；实测 SSM 通道与读 dbsync 桶权限均正常） | EC2 服务（已挂 i-08b0ef319d08eae38） | ① `AmazonSSMManagedInstanceCore`（Session Manager / Run Command 上机）；② 读 S3 中转桶 `css-dbsync-<账号>`（数据恢复 dump 中转）；③ `secretsmanager:GetSecretValue` **仅 `rds!*`**（RDS 托管主密码，恢复数据时机上自取，密码不过命令行）。⚠️ 挂此角色的网关机标签是 **`CssEnv=css-shared`**（角色本身只打 `Group`），**绝不能打 `css-test`/`css-uat`**——否则网关机会被那个环境的部署命令选中 |
| `css-non-prod-ec2-role` | 历史遗留：默认 VPC 旧 test 机的实例角色 | EC2 服务 | ECR 只读 + SSM 核心 + 读 `/css/test/*`。**旧 test 机已于 2026-07-28 删除，此角色已无使用者，可删**（保留也无害、零成本） |

### 用户（5 个，2026-07-29 更新）

| 用户 | 用处 | 权限 | key |
|------|------|------|-----|
| `css-app-test` / `css-app-uat` / `css-app-prod` | **应用代码访问 S3**（后端代码要求显式 AK/SK 环境变量，无法用实例角色） | ✅ 各自已挂内联策略 `css-app-<env>-s3`：桶级 `ListBucket`/`GetBucketLocation`/`ListBucketMultipartUploads` + 对象级 `PutObject`/`GetObject`/`DeleteObject`/`AbortMultipartUpload`/`ListMultipartUploadParts`，**Resource 精确到 `arn:aws:s3:::css-<env>-582797602427`(`/*`)**，跨桶一律无权 | ⏳ **暂不生成**（避免闲置长期凭证），用时再发 `create-app-s3-user.sh <env> --new-key` |
| `css-app-dev` | **本地开发直传真实 S3**（原来连 localhost:9000 的 MinIO）——不是部署环境，标签 `CssEnv=css-dev` | ✅ 同上，只限桶 `css-dev-582797602427` | ✅ **已生成**，写在工作区 `deploy-env/dev/backend.env`（不入库）。实测能读写删自己的桶、访问 test/prod 桶被拒 |
| `css-test` | **人工运维**：本机 aws cli 当前使用的身份 | Admin 组（全权）。建议后续改名并收权到最小集 | 有（本机 `~/.aws/credentials`） |

**建/刷新应用用户的脚本：`create-app-s3-user.sh`**（与 `create-iam.sh` 分开，因为它依赖桶先存在）

```bash
./create-app-s3-user.sh dev --new-key   # 建用户 + 挂策略 + 生成一对 access key（只打印这一次）
./create-app-s3-user.sh test            # 只建用户 + 挂策略，不生成 key
```

- 幂等：用户存在即复用，策略覆盖式刷新，标签补齐。
- **前置**：目标桶 `css-<env>-582797602427` 必须已由 `../13-s3/create-s3.sh <env>` 建好，否则脚本拒绝执行（策略不能指向不存在的资源）。

### 身份提供商（1 个）

| Provider | 用处 |
|----------|------|
| `token.actions.githubusercontent.com`（OIDC） | GitHub Actions **免长期密钥**换 AWS 临时凭证的信任入口——GitHub 不保存任何 AWS key，凭证 1 小时自动过期；哪个 workflow 能换哪个角色由上表"信任"列控制 |

## 可视化页面

**IAM 控制台**（全局服务，不分 region）：

- 角色列表直达：<https://console.aws.amazon.com/iam/home#/roles>
- 入口路径：控制台 → IAM → Roles / Identity providers / Users

在页面上看什么：

1. **Roles** 搜 `css-` 前缀：`css-deploy-{test,uat,prod}`、`css-ec2-{test,uat,prod}`、`css-gw-non-prod`（+遗留 `css-non-prod-ec2-role`）。**不应再看到 `css-gw-nonprod`**——2026-07-29 改名后旧角色已删除。
2. 点进某个 `css-deploy-<env>` → **Trust relationships** 页签：Federated 应是 GitHub OIDC provider，`sub` 条件含新旧两种格式、只信任对应分支/environment（`css-deploy-prod` 应是 `ref:refs/heads/main` 与 **`environment:main`**——若还看到 `environment:production` 说明是改名前的旧版，重跑 `create-iam.sh` 刷新）；→ **Permissions** 页签核对上表权限。
3. **Identity providers** 页：存在 `token.actions.githubusercontent.com` 一条。
4. **Users** 搜 `css-app-`：**四个**应用用户（`dev`/`test`/`uat`/`prod`），每个都应有一条内联策略 `css-app-<env>-s3`；
   **Security credentials 页签里只有 `css-app-dev` 有 access key**，其余三个应为空（用时再发，避免闲置凭证）。

## 状态/注意

- ✅ 已执行：OIDC provider + 三环境三件套 + 信任策略新格式修复（2026-07-28）；**environment 改名（`production` → `main`）后已重跑生效，prod 角色现信任 `repo:.../...:environment:main`（2026-07-29）**。`css-gw-non-prod` 由 06-ec2 网关脚本维护（2026-07-29 由 `css-gw-nonprod` 改名重建：**IAM 角色名不可修改**，脚本自动做了"建新 → `replace-iam-instance-profile-association` 换绑 → 删旧角色/profile"，重跑 `create-gateway.sh nonprod` 幂等）。
- ✅ **应用 S3 用户（2026-07-29）**：`css-app-{dev,test,uat,prod}` 四个用户均已建好并挂上"仅本环境桶"的内联策略（`create-app-s3-user.sh`）；**只有 dev 生成了 access key**，test/uat/prod 用时再发。
- 全部零成本，可随时重跑刷新信任/权限策略（改分支映射后重跑即可生效）。
- `css-ec2-<env>` 被 `../06-ec2/create-app-ec2.sh` 作为实例 profile 引用，改名会导致建机失败。
