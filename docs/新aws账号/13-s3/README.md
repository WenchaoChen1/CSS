# 13-s3 —— 各环境应用存储桶

应用上传的发票 / 目录 / 图片等文件存这里（后端 `S3_STORAGE_BUCKET_NAME`）。一环境一个桶，互不可见。

## 怎么用

```bash
cd docs/新aws账号/13-s3
./create-s3.sh          # 三个部署环境一次建齐（缺省 all=test/uat/prod）
./create-s3.sh uat      # 只建某一个
./create-s3.sh dev      # 本地开发桶（不在 all 里，要显式指定）
```

建桶同时会配好：**阻断一切公共访问** + SSE-S3 默认加密 + 版本控制 + 生命周期（未完成分段上传 7 天清理、
历史版本 30 天清理）+ 双标签（`Group` / `CssEnv`）+ 一份最小 CORS。

## 当前桶名（2026-07-29，共 5 个 ✅）

**命名规范：`css-<env>-<账号ID>`，全部带账号后缀**（2026-07-29 用户拍板）。
纯名 `css-test` / `css-prod` 早被别的 AWS 账号占用（S3 桶名是全球唯一命名空间，跨账号跨区域共用），
只有 `css-uat` 当时侥幸可建——但几个环境两种写法更糟，所以 uat 也重建为带后缀的名字，旧的空桶 `css-uat` 已删除。

| 用途 | 桶名 | 访问身份 | 说明 |
|------|------|----------|------|
| test | **`css-test-582797602427`** | IAM 用户 `css-app-test` | 原 `css-test-storage-582797602427` 的 102 个对象（59MB）已 `s3 sync` 迁入，**旧桶已退役删除** |
| uat | **`css-uat-582797602427`** | `css-app-uat` | 2026-07-29 由 `css-uat` 改名重建（空桶，无数据迁移） |
| prod | **`css-prod-582797602427`** | `css-app-prod` | 空，等生产上线 |
| dev（本地开发直传） | **`css-dev-582797602427`** | `css-app-dev`（**已生成 access key**） | 本地 dev 原本连 localhost:9000 的 MinIO，现改为直传真实 S3；key 已写进工作区 `deploy-env/dev/backend.env`。标签 `CssEnv=css-dev` |
| 运维 dump 中转 | `css-dbsync-582797602427` | 网关机角色 `css-gw-non-prod`（只读） | 数据库 dump 中转桶（`05-数据同步/restore-dump-via-gw.sh` 用），标签 `CssEnv=css-shared` |

> 判断桶归属只能用 `list-buckets`：`head-bucket` 对**别人的公开桶**也会返回成功（`css-test` 就是这样——
> 它在 ap-northeast-1、属于其他账号），拿它判断会误判成"我们已有"，后续所有 `put-*` 全部 AccessDenied。脚本已按此修正。

## 桶名变更后必须做的事

1. 改 `deploy-env/<env>/backend.env` 的 `S3_STORAGE_BUCKET_NAME`；
2. `11-parameter-store/put-params.sh <env>`；
3. 重新部署后端（`09-ssm-run-command/deploy-env.sh <env> core`）——桶名是运行时变量，不用重建镜像；
4. 若旧桶有数据：`aws s3 sync s3://旧桶 s3://新桶`（已对 test 做过），确认无误后用 `retire-bucket.sh` 退役旧桶（见下节）。

## 退役旧桶：`retire-bucket.sh`（✅ 已用它删掉 `css-test-storage-582797602427`）

```bash
./retire-bucket.sh css-test-storage-582797602427 css-test-582797602427       # 只比对，不删
./retire-bucket.sh css-test-storage-582797602427 css-test-582797602427 yes   # 比对通过后清空并删除源桶
```

先**逐对象比对**确认目标桶一个都不缺，再清空（含历史版本与删除标记，开了版本控制的桶不清干净删不掉）并删除源桶。不加第三个参数 `yes` 时只比对。

> ⚠️ **踩过的坑（脚本已修，别改回去）**：列对象时**绝不能在 `--query` 里带 `Key` 字段**。
> Windows 版 `aws.exe` 用 GBK 编码写 stdout，文件名里只要有一个非 GBK 字符（实测踩到 U+202F 窄空格）
> 就会在那一行**崩溃并静默截断**——同一个桶 `Contents[].[Key,Size]` 只吐 27 行就停，
> `Contents[].[ETag,Size]` 才是完整 102 行。截断后比对"通过"实际只覆盖了前一小部分对象，**会误删数据**。
> 所以脚本一律用 **ETag+Size 做内容指纹**（纯 ASCII，与文件名编码无关）比对，并在源桶列举为 0 时直接拒绝执行。

## 可视化页面

**S3 控制台**：<https://s3.console.aws.amazon.com/s3/buckets?region=us-east-1>

- 看什么：① 桶列表里 `css-*` 五个（test/uat/prod/dev/dbsync）；② 点进桶 → **Permissions** 页签，"Block public access" 应为 **On**；
  ③ **Properties** 页签确认默认加密 SSE-S3、Bucket Versioning 为 Enabled；
  ④ **Management** 页签看两条生命周期规则。

## 注意

- 应用访问 S3 用的是**显式 AK/SK**（代码要求 `S3_ACCESS_KEY_ID`/`S3_SECRET_ACCESS_KEY`，拿不到实例角色的临时凭证），
  对应 IAM 用户 `css-app-<env>`。当前状态（2026-07-29）：
  - ✅ **四个用户 `css-app-{dev,test,uat,prod}` 都已挂上各自桶的内联策略**（`css-app-<env>-s3`）：
    桶级 `ListBucket` / `GetBucketLocation` / `ListBucketMultipartUploads` + 对象级 `PutObject` / `GetObject` /
    `DeleteObject` / `AbortMultipartUpload` / `ListMultipartUploadParts`，**Resource 精确到本桶 ARN**，跨桶一律无权。
  - ✅ **只有 `css-app-dev` 生成了 access key**（本地开发要用），已写进 `deploy-env/dev/backend.env`。
    实测：dev 密钥能读写删自己的桶，访问 test / prod 桶被拒。
  - ⏳ **test / uat / prod 暂不生成 key**——避免闲置长期凭证，用时再发：
    `../07-iam/create-app-s3-user.sh <env> --new-key`（密钥只打印这一次）。key 绝不跨环境复用。
- CORS 现在是 `AllowedOrigins: ["*"]`（方便联调）；**上生产前要收成真实域名**。
- 版本控制开着：删对象只是加删除标记，实际空间由生命周期在 30 天后回收。
