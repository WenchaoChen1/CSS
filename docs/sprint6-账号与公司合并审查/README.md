# sprint6「账号与公司合并」系列提交审查

Felix 在 `sprint/sprint6` 上把四张 `*_member` 表合并进 `account`、把 store / restaurant / manufacturer_subdivision 合并进 `company` 表；
Lily、lucy 在这条线上继续开发 Team、平台用户管理、公司信息、Master Database、公司停用等功能。本目录是对这一系列提交的持续审查：
每当 sprint6 前进，就按同一套口径复核全部已知问题、审查新提交，并更新报告。

> 本目录含漏洞细节和基础设施信息，只能放在私有仓库，不要转到公开仓库。固定密码在所有文件里都已打码为 `<固定密码>`。

## 目录

| 文件 | 内容 |
|---|---|
| [`审查报告.md`](审查报告.md) | 当前版本的完整报告（结论、阶段表、高/中/低危、删表前提复核、驳回与更正、建议） |
| [`审查报告.html`](审查报告.html) | 同一份报告的页面版（可筛选、搜索全部问题），本地用浏览器直接打开 |
| [`findings.json`](findings.json) | 问题清单：每条问题的当前状态、级别、复核说明和证据。下一轮复核的输入 |
| [`沟通与决策记录.md`](沟通与决策记录.md) | 用户原话和已确认的决定（例如 H1 按设计接受、删表前提）。**继续审查前先读** |
| [`工具/recheck-workflow.js`](工具/recheck-workflow.js) | 复核 + 新提交审查 + 对抗式验证的 Workflow 脚本（参数化，每轮通用） |
| [`工具/apply_recheck.py`](工具/apply_recheck.py) | 把 Workflow 结果和人工裁定合并进 findings.json，并打印报告要用的数字 |
| [`工具/build_page.py`](工具/build_page.py) | 用 `page-template.html` + findings.json 生成报告页面 |
| [`工具/page-template.html`](工具/page-template.html) | 页面模板；手写部分每版按报告更新，表格由 findings.json 驱动 |

流程说明在 [`提示词/sprint6合并审查.md`](../../提示词/sprint6合并审查.md)，Claude Code 里输入 `/sprint6-merge-review` 即可按流程执行。

## 版本

| 版本 | 日期 | 后端 | 前端 | 结果 |
|---|---|---|---|---|
| 第 1 版 | 2026-11-09 | `c03cbcf6^..d49f0bd9`（Felix 28 个提交） | `ab279c09^..ea616539` | 105 条问题 |
| 第 2 版 | 2026-11-10 | `2582af89` | `7a2cccc2` | 新增 33 条 |
| 第 3 版 | 2026-11-13 | `f6891d8d` | `1aedac54` | 新增 33 条（范围加入 Lily、lucy）；未关闭 155 条，高危 9 |
| 第 4 版 | 2026-11-17 | `a4db1e5f` | `6eb46852` | 审查新提交新增 21 条；H1 按设计接受；按删表前提补充复核，新增 9 条、4 条不再计入；未关闭 **178** 条（高危 10、中危 46、低危 122） |

**下一轮的基线**：后端 `a4db1e5f`、前端 `6eb46852`，`prevLabel` 为 `第 4 版`，新问题编号从 **N97** 开始。

**下一轮先做**：2026-11-18 用户确认删除范围只包括 `company_back` 和 `deprecated_*` 表，`deprecated_*` 列和 9 张备份/映射表都不删（D9）。按这个范围的复核被用户暂停，还没做，待办见 [`沟通与决策记录.md`](沟通与决策记录.md) 第三节。

报告页面（claude.ai Artifact，私有，需在页面的 Share 菜单里分享）：https://claude.ai/artifact/HN54VEdu6TrnQT2VowCthE 。
没有这个页面权限的人，用本目录的 `审查报告.html` 即可。

## findings.json 字段

| 字段 | 含义 |
|---|---|
| `id` | 编号。F 开头是第 1 版发现的问题，N 开头是之后各版新发现的问题；编号不复用 |
| `lab` | 报告里的别名，例如 `H1`、`H6′`、`M1`；删表前提复核新增的标为 `删表` |
| `sev` / `psev` / `orig` | 当前级别 / 上一版级别 / 首次发现时的级别：`high`、`medium`、`low` |
| `st` / `prev` | 当前状态 / 上一版状态：`new`、`still_present`、`partially_fixed`、`worse`、`fixed`、`obsolete`、`accepted`（按设计接受）、`waived`（按已确认的前提不计入） |
| `text` | 问题标题 |
| `note` | 最近一次复核的说明，含 `文件:行号` 证据；多次补充按时间追加 |
| `hash` / `by` | 引入问题的提交 / 作者 |
| `file` | 主要位置 |
| `fix` | 修复提交 |
| `chg` | 本版是否有变化 |

未关闭 = `st` 不是 `fixed`、`obsolete`、`accepted`、`waived`。

## 范围外的问题

审查中顺带发现、但不属于本系列提交的问题单列在报告 3.3，不计入统计：

- **X1**：订单接口越权，main（prod）上已存在。用户 2026-11-17 决定暂不修。
- **X2**：`sms_sender`、`email_sender` 以 INFO 打印整条消息，含临时密码和验证码。
