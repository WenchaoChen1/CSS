# lark-sync

把 Lark（飞书国际版）云文档拉取为本地 Markdown。**单向只读——本地改动永远不会推回 Lark。**

## 快速开始

```bash
cd tools/lark-sync
cp .env.example .env.local     # 填入 App ID / Secret
node sync.js pull
```

## 命令

| 命令 | 说明 |
|------|------|
| `node sync.js pull` | 拉取 `config.json` 中全部文档；revision 未变则跳过 |
| `node sync.js pull <名称>` | 只拉取指定文档 |
| `node sync.js pull --force` | 忽略 revision 强制重新拉取 |
| `node sync.js status` | 对比本地与远程 revision，不写文件 |
| `node sync.js watch [秒]` | 轮询 revision，有变化才拉取（默认 30 秒，最小 5 秒） |

## 新增一篇文档

编辑 `config.json`，`url` 直接粘浏览器地址栏即可：

```json
{
  "name": "简短名称",
  "url": "https://xxx.jp.larksuite.com/docx/XXXXXXXXXXXX",
  "out": "../../docs/lark/文件名.md"
}
```

## 工作原理

1. 用 `app_id` + `app_secret` 换 `tenant_access_token`（**应用身份，不需要 OAuth 授权**）
2. 读文档元信息拿 `revision_id`，与 `.sync-state.local.json` 里的记录比对
3. 有变化才拉取全部 block，按 `parent_id`/`children` 还原树，转成 Markdown

`revision_id` 是文档的版本号，任何人改动都会 +1，所以它是可靠的变更信号。

## 权限要求

应用需开通云文档读取权限（`docs:document:readonly` / `drive:drive:readonly` 等）并**发布版本**。
若目标文档不在应用可见范围内，需要在文档「分享」里把应用加为协作者。

## 转换覆盖范围

| 已支持 | 说明 |
|--------|------|
| 标题 H1–H9 | Lark heading1 → Markdown `##`（`#` 留给文档标题） |
| 段落、无序/有序列表、待办 | 待办映射为 `- [ ]` / `- [x]` |
| 引用、引用容器 | 嵌套内容加 `>` 前缀 |
| 代码块 | 含语言标注（30+ 种语言映射） |
| 行内样式 | 粗体、斜体、删除线、行内代码、链接 |
| 分割线、@提及、公式 | 公式转 `$...$` |

**尚未转换**（会留 HTML 注释标记位置，不静默丢失）：

- **表格**：Lark 表格是嵌套块结构，需要额外还原逻辑
- **图片**：只输出 `![图片](lark-image:<token>)` 占位，未下载文件
- 画板、思维笔记、幻灯片等富媒体块

未知块类型会降级为纯文本并附注释说明。

## 文件说明

| 文件 | 是否提交 |
|------|----------|
| `sync.js`、`lib/` | ✅ 提交 |
| `config.json` | ✅ 提交（不含凭证） |
| `.env.local` | ❌ 含 App Secret，已被 gitignore |
| `.sync-state.local.json` | ❌ 本地 revision 记录，已被 gitignore |
| `docs/lark/*.md` | ⚠️ 拉取的业务文档，**默认会进 git**，按需决定 |

## 注意

生成的 Markdown 顶部有自动生成标记，**不要直接编辑**——下次 `pull` 会覆盖。
