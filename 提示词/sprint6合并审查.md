# 提示词：sprint6「账号与公司合并」系列提交持续审查

> 用途：sprint/sprint6 每前进一段，就让 AI（Claude Code 等）按同一套口径重新复核已有问题、审查新提交，并更新报告。
> 用法（任选其一）：
> - Claude Code 里输入 `/sprint6-merge-review`（命令文件 `.claude/commands/sprint6-merge-review.md` 指向本文）；
> - 或直接对 AI 说：「按 `提示词/sprint6合并审查.md` 再复核一次 sprint6 合并审查」；
> - 或把本文「## 提示词正文」以下的内容整段复制给 AI。
>
> 资料都在 [`docs/sprint6-账号与公司合并审查/`](../docs/sprint6-账号与公司合并审查/README.md)：报告、问题清单 `findings.json`、
> 沟通与决策记录、工具脚本。首轮审查：2026-11；当前进度见该目录 README 的版本表。

---

## 提示词正文

你是 CSS（Chain Serve）项目的代码审查员。请**完整**执行下面的流程，不要跳步，不要只给计划。全程用中文汇报。

### 0. 目标

Felix 在 sprint/sprint6 上做了「四张 `*_member` 表合并进 account、store / restaurant / manufacturer_subdivision 合并进 company 表」
的系列提交，Lily（Team、平台用户管理、操作日志）和 lucy（公司信息、地址、Master Database、公司停用）在此基础上继续开发。
每一轮要做四件事：

1. 把上一版报告里的**每一条**问题对照最新代码复核：仍存在、部分修复、更严重、已修复、不再适用，并重新评估严重度；
2. 审查上一版之后合入 sprint6 的新提交，找出新问题，逐条做对抗式验证；
3. 给每条未关闭的问题写（或按新代码重写）建议解决方案，部分修复的写明修好了什么、还剩什么；
4. 更新问题清单、Markdown 报告和报告页面，并在沟通记录里补上本轮的用户决定。

### 1. 约束（必须遵守）

- **只读**：不修改、不提交前后端仓库的代码；只允许 `git fetch` 和在 sprint/sprint6 上 `git pull --ff-only`。
  先记录两个仓库当前所在分支；如果必须切分支，做完一定切回原分支（工作区 CLAUDE.md「分支卫生」）。
  后端仓库根目录可能有未跟踪文件（例如 `company`），不要动它。
- **不连数据库、不跑迁移**：结论全部来自读代码和迁移文件；报告里要写明「没有连库或运行测试验证」。
- **口令打码**：迁移 `4b52dd3297e5` 里的 dev admin 固定密码、test/uat 统一口令，一律写成 `<固定密码>`。
  工具脚本会从迁移文件里读出原文做检查，任何会提交的文件里都不要出现原文。
- **prod 是未脱敏真实数据**；uat/prod 已部署到 sprint5，`main`/`uat` 的迁移 head 是 `731ddff784cc`（D20，第 7 版核实；工作区说明里的 `b3d9f1a2c4e5` 已过时），这批迁移都还没执行。每轮先用 `git ls-tree` 读 `origin/main` 的迁移文件确认 head，不要照抄。
- 审查代理和汇总都不要编造：每条结论都要有 `文件:行号` 和提交哈希。

### 2. 已确认的前提和决定（以此为准，详见沟通与决策记录）

- **H1（dev admin 账号 `dev.admin@yopmail.com`）是有意创建的，按设计接受，不列为风险**（状态 `accepted`）。
  用户会在部署后自行修改密码。只在说明里保留提醒（yopmail 公共邮箱、迁移会在每个新库按固定密码重建），不再计入统计。
  N2（dev admin 对所有公司放行等权限设计）仍按风险跟踪，除非用户另有决定。
- **`company_back` 只是备份，将来会删除；`deprecated_*` 表将来也会删除，这些表都不再使用。**
  复核时以此为前提：依赖这些表「还能找回数据」的结论不再成立；删表前必须完成的事项单独列出。
- **`deprecated_*` 表审查时当作不存在**（D22，2026-11-19）：它们以后都会删除，不能再拿来当找回或核查数据的依据，也不因长期保留 PII 算问题；只有代码还在查询、写入或映射这些表，或其它表和它们有外键关联，才算问题。
- **删除范围只包括 `company_back` 和 `deprecated_*` 表；`deprecated_*` 列和 9 张 `*_backup` / 映射表都不删除**（2026-11-18，D9）。
  第 5 版已按这个范围复核。注意 `b8e906f7` 把这 9 张备份表在新库里改名为 `deprecated_*`，与 D9 冲突，
  去留待用户决定（N93，沟通与决策记录第三节）；用户决定前，按「保留」处理。
- **sprint6 已合入 `test` 分支**（D13，2026-11-18）：test 环境很可能已执行本系列迁移；uat/prod 还没执行。
- **test 也被合进了 sprint6**（D20，Felix 2026-11-19）：sprint6 与 `origin/test` 代码树相同，test 上原来独有的提交按本系列审查（N136）。每轮用 `git diff <上一版基线> <合并提交>` 看合并的净改动，不要只看非合并提交。
  不要写「sprint6 尚未部署到任何环境」。
- **本地库例外**（D12）：只有用户明确要求时才在本地库跑迁移；审查代理始终只读代码、不连任何库。
- **团队书面答复的处理原则**（2026-11-19，D19）：设计或需求取舍按设计接受（`accepted`）；环境数据和发布流程的说法没法连库验证，
  按团队确认的前提不计入（`waived`），但要指出代码里还有没有入口会继续产生这种数据；「已修复」「问题已不存在」「接口已不再使用」
  「表已废弃」必须在代码里找到证据（「不再使用」要查前后端有没有调用方、接口是否还挂在路由上）；答复没答到点或与代码不符的，
  状态不变并列出回问问题。复核时不要推翻按答复关闭的条目，除非代码事实变了。
- **X1（订单接口越权）是 main 上已存在的问题，不属于本系列**，单列为范围外，不计入统计；用户暂不修。
- **D25 的三库只读数据核实以数据为准**（2026-11-20）：另一台电脑在 test / uat / prod 只读查过数据，结论写在各条说明的「第 9 版数据核实」段落和报告「〇-E」里，并按数据调过 7 条的级别。复核时不要用只读代码得出的判断推翻它；建议解决方案里已被 D25 回答的查询，写成「D25 已查」的结果并说明升级前是否还要再查。两台电脑的结论合并时，已推送的编号优先（D21）。
- 审查范围包含 Felix、Lily、lucy 三人的提交；新问题要注明作者。
- 迁移改写（改已推送迁移的内容或 down_revision、删已推送的 revision）统一记在 F6，不在各条里重复计数。
- 一个根因只记一条；新提交只是放大已知问题时，并入已知问题并在说明里补充。

### 3. 流程

#### 3.1 拉代码，确定本轮范围

```bash
cd <工作区>/CSS_backend-main   && git branch --show-current && git status --short && git fetch --all --prune && git pull --ff-only
cd <工作区>/CSS_frontend-main  && git branch --show-current && git status --short && git fetch --all --prune && git pull --ff-only
```

- 上一版的基线提交写在 `docs/sprint6-账号与公司合并审查/README.md` 的版本表里。
- 列出新提交：`git log --no-merges --format='%h %an %ad %s' --date=format:'%m-%d %H:%M' <上一版基线>..HEAD`，
  以及每个提交的 `git show --stat`。
- 迁移：`git diff --name-status <基线>..HEAD -- core_app/src/app/migrations/versions`；从 uat/prod 的 head（现为 `731ddff784cc`）走一遍
  revision / down_revision，确认是否单一 head、有没有改写或删除已推送的迁移。
- 检查 `origin/sprint/sprint6_permissions` 是否已合入（N34 的配套代码）：`git merge-base --is-ancestor <提交> HEAD`。

#### 3.2 准备 Workflow 参数

用 `docs/sprint6-账号与公司合并审查/工具/recheck-workflow.js`（Workflow 工具的 `scriptPath`），`args` 为：

- `ctx`：背景说明。写清楚两个仓库路径、上一版基线和当前 HEAD、本轮每个非合并提交（哈希、作者、标题、改了哪些模块）、
  新迁移和迁移链状态、`sprint6_permissions` 是否合入、环境状态（uat/prod 在 `731ddff784cc`，prod 未脱敏），
  以及第 2 节的前提和决定。
- `findingsPath`：`findings.json` 的绝对路径。
- `prevLabel`：上一版的名称，例如 `第 4 版`。
- `baseBe` / `baseFe`：上一版的后端、前端基线提交。
- `batches`：把 findings.json 里**所有**条目（含已关闭的，用于确认没有回归）按领域分批，每批 6–8 条：
  迁移、账号与 me、公司、商品与门店、Team、onboarding、平台用户管理、设置与公司信息、前端、已关闭项。
- `withAdvice: true`（第 10 版起）：复核后仍未关闭的条目同时写 `advice`（建议解决方案），部分修复的写 `done` / `remain`，
  每批再由另一个代理独立复核（是否对症、在现有代码里是否可行、是否和已确认的决定冲突）。
- `lightBatches`（可选）：本轮新提交很少时，把上一版已关闭的条目放这里（每批 12–20 条），只查新提交有没有让它们回归；
  这时 `batches` 只放未关闭的条目。新提交多的轮次不要用，全部放进 `batches`。
- 增量复核时可以加 `skipAdviceVerify: true`（建议在第一段已经独立复核过，增量只是按新提交修订）和 `coarseVerify: true`（候选按仓库分组验证，代理更少）；
  `apply_delta.py` 加 `--partial` 时只叠加增量结果里有的条目。背景说明里要写清楚：清单里的 `sol` 是底稿，只改和新提交或数据结论不一致的地方。
- `finders`：按本轮提交的领域各派一个审查代理（6–8 个），每个写明要看的提交、文件和重点；
  另外固定加两个：`migrations`（迁移链、PG16 兼容、存量数据安全、downgrade、改写已推送迁移）和
  `security-cross`（横向安全：IDOR、只校验 token 不校验公司归属、dev admin / 平台 admin、账号接管、敏感字段泄露）。

#### 3.3 运行 Workflow，汇总结果

- **审查途中 sprint6 又前进了怎么办**（第 5 版遇到过）：Workflow 跑着时不要 pull，代理会读到不一致的代码。
  已跑完的部分先用 `apply_recheck.py --out <scratchpad>/findings_mid.json` 写成中间稿；再拉到最新，
  用同一个 `recheck-workflow.js` 跑增量（`findingsPath` 指向中间稿，`baseBe`/`baseFe` 用第一段的 HEAD，
  背景说明只写新提交），最后用 `工具/apply_delta.py` 叠加，`prev`/`psev` 会保持上一版的值。
  定一个冻结点，冻结后再推送的提交写进报告「冻结点之后」一节，留到下一轮。
- Workflow 中途被打断（额度、网络）时不要整轮重跑：已完成代理的结果在会话目录的 `workflows/<runId>.json` 里（含原始参数和 `result`），
  用同一个脚本和**完全相同**的参数加 `resumeFromRunId` 续跑；或者像第 10 版那样，把已有结果写进一个只补跑缺失部分的续跑脚本。
- Workflow 返回 `{recheck, review}`，存成 scratchpad 里的 `wf_result.json`。
  在 Windows 上运行工具脚本前设 `PYTHONUTF8=1`。
- 统计 recheck 的状态迁移、级别变化，逐条读 review 的全部 verdict（`idx` 从 0 开始，对应 `group.items[idx]`）。
- 写 `decisions.json`（格式见 `工具/apply_recheck.py` 开头的说明）：
  - 新问题编号接着上一版最大的 N 号往下编；同一根因的多条候选合成一条；
  - 已知问题的延续放进 `merged`，并在对应条目的 `overrides.append` 里写一句本轮变化；
  - 真实存在但不是本系列引入的问题放进 `rejected`，在报告「范围外」小节单列（像 X1、X2 那样）；
  - 验证代理的级别和本报告定级不一致时，在 `sev_note` 里写明理由。
- 定级口径（第 4 版起沿用）：需要能读应用日志才能利用的凭据泄露定中危；需要 CSS Admin 主动操作、
  且软删数据在库里可恢复的定中危；只影响边界情况、有绕法的定低危。

#### 3.4 人工核对

- 所有新的高危、所有状态变成 fixed 的高危和中危，必须亲自读代码确认；
- 发现的范围外问题，用 `git show origin/main:<路径>` 确认是否在 prod 代码上存在。

#### 3.5 生成数据、报告和页面

```bash
cd docs/sprint6-账号与公司合并审查/工具
python3 apply_recheck.py --findings ../findings.json --result <scratchpad>/wf_result.json \
    --decisions <scratchpad>/decisions.json --backend <工作区>/CSS_backend-main --out ../findings.json [--keep-closed-notes]
python3 gen_report_tables.py --findings ../findings.json --report ../审查报告.md \
    --label '第 N 版' --backend-rev <后端 HEAD> --frontend-rev <前端 HEAD>
```

- `apply_recheck.py` 会用本轮复核说明**替换**每条的 `note`，并自动把上一版说明里从「（以下为…保留）」「第 N 版补充」「第 N 版补记」「第 N 版数据核实」开始到末尾的段落接回去（团队答复的核实说明、D22 / D23、D25 的数据核实等）。以后要长期保留的补充说明，另起一行并用这几种开头。用了 `lightBatches` 的轮次加 `--keep-closed-notes`，已关闭且没变化的条目保留原说明。运行后仍要抽查几条对比上一版。
- 脚本最后会列出「未关闭但没有建议解决方案」「部分修复但没有 done / remain」的条目，都应为空；新问题的建议写在 `decisions.new[].sol` 里。
- 每条未关闭的问题都要有 `sol`（建议解决方案）；每条「部分修复」都要有 `done`（已修好）和 `remain`（还剩）各一两句话。页面直接显示在问题下面，报告「〇-A」「〇-C」由 `gen_report_tables.py` 按 findings.json 生成，不要手工改这两节。**每版都要按新基线重写**（`withAdvice`）。建议要遵守已确认的决定：已推送的迁移不原地修改、`deprecated_` 表视为不存在、按设计接受的条目不推翻。
- 按脚本打印的数字更新 `审查报告.md`：页头（日期、当前代码、上一版基线、本版新增审查的提交数）、
  〇 结论与数字表、一 阶段表（本版新增的提交加粗）、二 阻断项、三 高危（3.1 未关闭 / 3.2 已关闭或降级 / 3.3 范围外）、
  四 中危（4.1 本版新增 / 4.2 前几版现状）、五 低危、六 驳回与更正、七 建议。
- 更新 `工具/page-template.html` 里手写的部分（与 Markdown 的结论一致），然后：
  `python3 build_page.py --findings ../findings.json --template page-template.html --backend <工作区>/CSS_backend-main --out ../审查报告.html --standalone`
- 如果当前会话能用 claude.ai Artifact，把不带 `--standalone` 的页面发布到 README 里记录的报告链接（更新同一个链接，不要新建）。
- 在 `README.md` 的版本表里加一行本版；在 `沟通与决策记录.md` 里补上本轮用户的原话和决定。

#### 3.6 收尾检查

- 两个仓库仍在原分支，`git status` 和开始时一样（只多了 pull 下来的提交）；
- 报告、页面、findings.json 里没有固定密码原文（工具脚本会检查）；
- 向用户汇报：未关闭数（高/中/低）、本版新增、修好了什么、更严重了什么、范围外发现，以及需要用户决定的事。

### 4. 状态和严重度口径

| 状态 | 含义 |
|---|---|
| `new` | 本版新发现 |
| `still_present` | 仍存在 |
| `partially_fixed` | 部分修复，说明里写剩下什么 |
| `worse` | 新提交让它更严重（新入口、影响面扩大） |
| `fixed` | 已修复，写修复提交 |
| `obsolete` | 相关代码已删除或重构，问题不再适用 |
| `accepted` | 团队确认按设计接受，不列为风险（例如 H1） |
| `waived` | 按已确认的前提不计入（例如 D7 下的 F8、D9 下的 N91、D19 下团队确认的环境数据）；`apply_recheck.py` 不会用复核结果改掉 `accepted` / `waived`，要改须在 `decisions.overrides` 里显式给 `st` |

严重度：high = 跨租户/越权/后门/凭据泄露、不可逆数据丢失或错位、主流程不可用、uat/prod 升级必然失败；
medium = 公司内越权、局部功能坏掉、可恢复的数据问题、明显的行为回归；low = 边界情况、代码质量、一致性、测试缺失。
