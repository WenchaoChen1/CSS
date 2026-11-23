export const meta = {
  name: 'sprint6-merge-review-recheck',
  description: 'Re-verify the sprint6 account/company merge review findings against the latest code and review the new commits',
  whenToUse: 'Run from 提示词/sprint6合并审查.md (or /sprint6-merge-review) once sprint/sprint6 has moved past the baseline recorded in findings.json',
  phases: [
    { title: 'Recheck', detail: 'every finding of the previous round against HEAD, in batches' },
    { title: 'Advise', detail: 'independently verify the suggested fixes and the fixed / still-left lines (withAdvice only)' },
    { title: 'Find', detail: 'one reviewer per area of the commits merged since the previous round' },
    { title: 'Verify', detail: 'adversarially verify the candidates, grouped by area' },
  ],
}

// args (all required unless marked optional):
//   ctx          string  background: repos, baseline and HEAD commits, the new commits (hash, author, subject),
//                        new migrations, environment state, read-only rules. See 提示词/sprint6合并审查.md §3.2.
//   findingsPath string  absolute path of findings.json (the previous round's findings)
//   prevLabel    string  e.g. '第 4 版'
//   baseBe/baseFe string previous round's backend / frontend commits (git log -p <base>..HEAD)
//   batches      string[][] finding ids to recheck, grouped by area (6–8 per batch); every open and closed id once
//   finders      {key, prompt}[] one reviewer per area of the new commits
//   sevDef       string  optional override of the severity definition
//   repliesPath  string  optional: JSON {id: [{seg, text}]} with the development team's written replies; when given,
//                        each recheck result also judges the reply (reply_verdict / reply_check, per D19)
//   lightBatches string[][] optional: ids that were already closed in the previous round, in larger batches (12–20).
//                        They are only checked for regressions caused by the commits since baseBe / baseFe. Use it
//                        when few commits landed; otherwise put every id in `batches`.
//   withAdvice   boolean optional: every finding still open after the recheck also gets `advice` (建议解决方案) and,
//                        when partially fixed, `done` / `remain`; a second agent then verifies them per batch.
//   skipAdviceVerify boolean optional: with withAdvice, skip that second agent (an incremental pass whose advice was
//                        already verified in the first pass and is only being revised).
//   coarseVerify boolean optional: verify the new-commit candidates in one group per repository (up to 8 each)
//                        instead of one group per directory; fewer agents when few commits landed.

const A = args || {}
for (const k of ['ctx', 'findingsPath', 'prevLabel', 'baseBe', 'baseFe', 'batches', 'finders']) {
  if (A[k] === undefined || A[k] === null) throw new Error(`missing args.${k}`)
}

const SEV_DEF = A.sevDef || `严重度：high = 跨租户/越权/后门/凭据泄露、不可逆数据丢失或错位、主流程不可用、uat/prod 升级必然失败；medium = 公司内越权、局部功能坏掉、可恢复的数据问题、明显的行为回归、需要额外前提（如能读应用日志）才能利用的凭据泄露；low = 边界情况、代码质量、一致性、测试缺失。`

const RULES = `规则：只读。不要修改任何文件、不要 git checkout/switch/reset/stash/pull/fetch、不要连接任何数据库或运行迁移、不要发网络请求。用 git show / git diff / git log / grep / 读文件。所有结论用中文，证据写 文件:行号（以当前 HEAD 为准）和 commit hash。代码里如有明文密码，用 <固定密码> 代替，不要写出原文。`

const RECHECK_SCHEMA = {
  type: 'object',
  properties: {
    results: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          status: { type: 'string', enum: ['still_present', 'fixed', 'partially_fixed', 'worse', 'obsolete'] },
          changed_since_prev: { type: 'boolean' },
          fixed_by: { type: 'array', items: { type: 'string' } },
          severity_now: { type: 'string', enum: ['high', 'medium', 'low', 'none'] },
          evidence: { type: 'string' },
          note: { type: 'string' },
          reply_verdict: { type: 'string', enum: ['none', 'holds', 'partly', 'not_hold', 'design_accept', 'premise_waive'] },
          reply_check: { type: 'string' },
          advice: { type: 'string' },
          done: { type: 'string' },
          remain: { type: 'string' },
        },
        required: ['id', 'status', 'changed_since_prev', 'fixed_by', 'severity_now', 'evidence', 'note', 'reply_verdict', 'reply_check']
          .concat(A.withAdvice ? ['advice', 'done', 'remain'] : []),
      },
    },
  },
  required: ['results'],
}

function recheckPrompt(ids) {
  return `${A.ctx}

${RULES}

任务：复核${A.prevLabel}报告中的问题在当前 HEAD 上的现状。问题清单在 ${A.findingsPath}（JSON 数组）。字段：id、lab（报告里的 H/M 编号）、sev / st（${A.prevLabel}的级别和状态；st=new 表示${A.prevLabel}新发现，accepted 表示团队已按设计接受）、psev / prev（再上一版的级别和状态）、text（标题）、note（${A.prevLabel}的复核说明，含证据）、hash、file、by（作者）、fix（修复提交）。用 python3 或 jq 取出这些 id：${ids.join(', ')}。

对每一条：
1. 读当前 HEAD 上的相关代码（修复可能在别处：中间件、DI、新迁移、新服务）。用 git log -p ${A.baseBe}..HEAD（后端）/ ${A.baseFe}..HEAD（前端）看相关文件后来改了什么；也要 grep 新增代码里有没有同类问题的新入口或新绕过。相关文件本轮没动，也要快速确认结论和行号仍成立。
2. 判定 status（相对${A.prevLabel}，最终结论按 HEAD 代码）：
   - still_present：仍然成立
   - fixed：已修复（fixed_by 填 commit；说明怎么修的、是否完整；${A.prevLabel}已判 fixed/obsolete 的要确认没有回归）
   - partially_fixed：部分修复，说明还剩什么
   - worse：本轮新提交让问题更严重（多了新入口、影响面扩大）
   - obsolete：相关代码被删除/重构，问题不再适用（要确认没有以别的形式继续存在）
   st=accepted 的条目：只确认实现有没有变化，status 按代码事实填，note 里注明"团队已按设计接受"。
3. changed_since_prev：相关代码或结论自${A.prevLabel}以来是否有变化。
4. severity_now：按现状给 high/medium/low；fixed/obsolete 填 none。${SEV_DEF}
5. evidence：HEAD 上 文件:行号 + 关键代码片段（简短）。note：1–3 句中文说明，重点说与${A.prevLabel}相比的变化（没变化就直说"本轮未改动"）。
以代码为准，${A.prevLabel}的描述也可能有误，发现就指出。
${A.repliesPath ? REPLY_RULES : '6. reply_verdict 填 none，reply_check 填空字符串。'}
${A.withAdvice ? ADVICE_RULES : ''}`
}

const ADVICE_RULES = `7. 对复核后仍未关闭的条目（status 为 still_present / partially_fixed / worse，且上一版 st 不是 accepted / waived）写 advice（建议解决方案），让开发可以直接照着做：
   - 2–4 句中文。先说改哪里、怎么改（文件、函数、接口或迁移，按 HEAD 上的位置），再说存量数据怎么处理、怎么验证（要补的测试，或上线前要跑的只读 SQL）。
   - 给最小可行的改法；有明显取舍时给出推荐方案和一个备选。需要产品或用户先做决定的，写清楚要决定什么、推荐哪一个、决定之后代码怎么改。
   - 必须遵守背景里的前提和决定：已推送的迁移不再原地修改，一律新增迁移（test 已执行过旧版的，写幂等的修复迁移）；deprecated_ 表视为不存在，不能建议从这些表读数据；按设计接受的条目不要建议推翻；不要建议在 uat/prod 上做没有备份的破坏性操作。
   - 不要写空话（「加强校验」「完善测试」「优化逻辑」），要具体到校验什么、测哪条路径。团队答复不成立的条目，建议里要包含对答复的回应（哪里和代码不符、需要团队确认什么）。
   - status 为 partially_fixed 时另外写 done（哪部分已经修好、靠哪个提交，一句话，不超过约 70 个汉字）和 remain（还剩什么问题、谁会碰到、后果，一到两句，不超过约 110 个汉字，可带一个关键位置），开头不要重复「已修好」「还剩」这几个字。
   已关闭的条目（status 为 fixed / obsolete，或上一版 st 为 accepted / waived）advice、done、remain 都填空字符串；status 不是 partially_fixed 时 done、remain 填空字符串。`

function lightPrompt(ids) {
  return `${A.ctx}

${RULES}

任务：下面这些条目在${A.prevLabel}已经关闭（st 为 fixed / obsolete / accepted / waived）。本轮只确认${A.prevLabel}之后的新提交有没有让它们回归，或者让关闭的理由不再成立。问题清单在 ${A.findingsPath}（JSON 数组，字段：id、lab、sev、st、text、note、hash、file、by、fix）。用 python3 或 jq 取出这些 id：${ids.join(', ')}。

做法：
1. 先看本轮改动的范围：后端 git diff --stat ${A.baseBe}..HEAD 和 git log --oneline ${A.baseBe}..HEAD，前端 git diff --stat ${A.baseFe}..HEAD 和 git log --oneline ${A.baseFe}..HEAD；需要时读具体 diff。
2. 对每一条：读它的 text、note、file、fix，判断它涉及的代码（文件、函数、接口、迁移）有没有被本轮改动碰到，本轮新增的代码里有没有同类问题的新入口。
   - 没碰到：status 保持${A.prevLabel}的结论（st 为 fixed 填 fixed，obsolete 填 obsolete；accepted / waived 按代码事实填关闭前的状态，通常是 still_present），changed_since_prev 填 false，note 写「本轮未改动」加一句原结论，evidence 写你确认没碰到的依据（例如相关文件不在本轮 diff 里，并快速确认关键代码在 HEAD 上还在）。
   - 碰到了：读 HEAD 代码核对，按代码事实填 status（回归了就填 still_present 或 worse，并在 note 里写清楚哪个提交造成的），changed_since_prev 填 true。
3. severity_now：status 为 fixed / obsolete 填 none；其余沿用清单里的 sev，除非代码事实变了。
4. fixed_by：沿用清单里 fix 字段的提交哈希（空格分隔，拆成数组）；没有就填空数组。
5. reply_verdict 填 none，reply_check 填空字符串${A.withAdvice ? '；advice、done、remain 都填空字符串' : ''}。
以代码为准；如果发现${A.prevLabel}的关闭结论本身有误（不是本轮改动造成的），也要指出并按代码事实填 status。`
}

const ADVICE_SCHEMA = {
  type: 'object',
  properties: {
    items: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          ok: { type: 'boolean' },
          problem: { type: 'string' },
          advice: { type: 'string' },
          done: { type: 'string' },
          remain: { type: 'string' },
        },
        required: ['id', 'ok', 'problem', 'advice', 'done', 'remain'],
      },
    },
  },
  required: ['items'],
}

function advicePrompt(items) {
  const list = items.map(r => `[${r.id}] 复核状态 ${r.status}，级别 ${r.severity_now}\n  复核说明: ${r.note}\n  证据: ${r.evidence}\n  advice（建议解决方案）: ${r.advice}${r.status === 'partially_fixed' ? `\n  done（已修好）: ${r.done}\n  remain（还剩）: ${r.remain}` : ''}`).join('\n\n')
  return `${A.ctx}

${RULES}

任务：独立复核另一位审查员给下面这些未关闭问题写的「建议解决方案」（advice），以及部分修复条目的 done / remain。问题原文在 ${A.findingsPath}（按 id 取 text、note、file、reply、replyv）。默认立场是怀疑：逐条去 HEAD 代码里核实。

检查要点：
1. 对症：advice 是否解决 note 里的根因，而不是只处理表象；照它做完，这条问题能不能关闭。漏掉的入口要补上。
2. 可行：提到的文件、函数、接口、权限码、依赖、迁移在 HEAD 上是否存在，位置对不对；改法是否和周围代码的写法一致；有没有更小、更稳的改法。
3. 副作用和冲突：会不会破坏别的调用方或存量数据；是否违反背景里的前提和决定（原地改已推送的迁移、从 deprecated_ 表读数据、推翻按设计接受的条目、在 uat/prod 上做没有备份的破坏性操作）；是否和别的已知问题的修法打架。
4. 存量数据和验证：需要动数据时是否写明新增迁移、幂等、test 已执行过旧版怎么办；验证方法是否具体（测哪条路径、跑什么只读 SQL）。
5. 表述：具体、好懂、没有空话，2–4 句；需要产品或用户决定的写清楚要决定什么、推荐哪个。
6. done / remain（只有部分修复的条目有）：事实是否准确（修复提交用 git show --stat 核对），有没有说反，remain 是否具体写出还剩的问题、谁会碰到、后果；开头不要重复「已修好」「还剩」。
有问题就直接改好，ok 填 false，并在 problem 里说明改了什么、为什么；没问题原样照抄，ok 填 true，problem 填空字符串。不是部分修复的条目 done、remain 填空字符串。每条都要输出。

待复核（${items.length} 条）：
${list}`
}

const REPLY_RULES = `6. 开发团队对部分条目给了书面答复，在 ${A.repliesPath}（JSON：id → [{seg, text}]，同一条可能有前后不一致的几段答复）。答复是按团队拿到的那一版报告写的，修复可能在之后的提交里，以 HEAD 代码为准。对有答复的条目，按 D19 判断 reply_verdict：
   - holds：答复说「已改/已修复/已删除/不存在/不再使用/已废弃」，代码里找到了证据（status 应为 fixed 或 obsolete）；
   - partly：答复部分成立（例如只修了一半、或只对部分入口成立），写清楚剩什么；
   - not_hold：答复与代码不符、没答到问题本身，或几段答复互相矛盾（写清楚哪里不符，可回问团队的问题）；
   - design_accept：答复是设计或需求取舍（「需求如此」「正常需求」「不用改」），代码确实按这个设计在工作，可以按设计接受；如果这个取舍会带来跨租户、数据丢失等高风险，仍判 design_accept，但在 reply_check 里写明风险，由人工决定；
   - premise_waive：答复是环境数据或发布流程方面的说法（「uat/prod 没有这种数据」「同时上线」「downgrade 不会执行」「测试不影响业务」），无法连库验证，可按团队确认的前提不计入；要指出代码里是否仍有入口会继续产生这种数据；
   - none：这条没有答复。
   reply_check：1–2 句中文，说明怎么核实的（文件:行号或提交），没有答复就填空字符串。status 和 severity_now 仍按代码事实填，不要因为答复而改。`

const FIND_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          repo: { type: 'string', enum: ['backend', 'frontend', 'both'] },
          file: { type: 'string' },
          line: { type: 'string' },
          commit: { type: 'string' },
          author: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          category: { type: 'string' },
          why: { type: 'string' },
          scenario: { type: 'string' },
          evidence: { type: 'string' },
        },
        required: ['title', 'repo', 'file', 'line', 'commit', 'author', 'severity', 'category', 'why', 'scenario', 'evidence'],
      },
    },
  },
  required: ['findings'],
}

function findPrompt(f) {
  return `${A.ctx}

${RULES}

任务：在${A.prevLabel}之后合入 sprint6 的新提交里找问题。${f.prompt}

已知问题清单在 ${A.findingsPath}（只需看 id/text/file/st 了解已知问题，不要重复报告；新提交让已知问题以新形式出现或被放大时，在 title 里注明"与 Fxx/Nxx 相关"；st=accepted 的是团队已按设计接受的，不要再报）。
只报告有代码证据的真实问题，每条给出 文件:行号、commit、作者、触发场景。不要报告纯风格问题。宁可少报也不要编造。
${SEV_DEF}`
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          idx: { type: 'integer' },
          verdict: { type: 'string', enum: ['confirmed', 'rejected', 'duplicate_existing', 'duplicate_candidate'] },
          dup_of: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low', 'none'] },
          title: { type: 'string' },
          detail: { type: 'string' },
          evidence: { type: 'string' },
          reason: { type: 'string' },
        },
        required: ['idx', 'verdict', 'dup_of', 'severity', 'title', 'detail', 'evidence', 'reason'],
      },
    },
  },
  required: ['verdicts'],
}

function verifyPrompt(group) {
  const list = group.items.map((c, i) => `[${i}] (${c.finder}, ${c.severity}, ${c.commit}, ${c.author}) ${c.title}\n  文件: ${c.file}:${c.line}\n  原因: ${c.why}\n  场景: ${c.scenario}\n  证据: ${c.evidence}`).join('\n\n')
  return `${A.ctx}

${RULES}

任务：对抗式验证下面这些"本轮新提交引入的问题"候选（同属 ${group.key}）。默认立场是怀疑：逐条去 HEAD 代码里找能推翻它的证据（调用方其实做了校验、该路径不可达、字段其实有过滤、中间件已拦截、迁移顺序保证了前提、问题其实在 ${A.baseBe} 之前就存在等）。证据不足时判 rejected。

候选（idx 从 0 开始）：
${list}

对每条输出：
- verdict：confirmed / rejected（reason 说明；如果问题真实存在但不是本轮引入，也判 rejected，并在 reason 写明"存量问题"和它在哪个分支上存在）/ duplicate_existing（与已知问题重复或只是已知问题的延续，dup_of 填 Fxx 或 Nxx；已知问题在 ${A.findingsPath}）/ duplicate_candidate（与本组另一条候选重复，dup_of 填那条的 idx）
- severity：核实后重新给（rejected 填 none）。${SEV_DEF}
- title：一句中文问题标题（精确，可修正候选原标题的错误）
- detail：2–4 句中文，说明问题、触发条件、影响，并写明提交和作者
- evidence：HEAD 上 文件:行号 + 关键代码
- dup_of 不适用时填空字符串。`
}

function groupKey(c) {
  if (A.coarseVerify) return c.repo
  const f = (c.file || '').split(/[,，、（ ]/)[0]
  if (f.includes('migrations/versions')) return c.repo + ':migrations'
  const parts = f.split('/').filter(Boolean)
  return c.repo + ':' + parts.slice(0, Math.min(parts.length - 1, 5)).join('/')
}

const OPEN_ST = ['still_present', 'partially_fixed', 'worse']

async function adviseBatch(results, label) {
  if (!A.withAdvice || A.skipAdviceVerify) return results
  const todo = results.filter(r => OPEN_ST.includes(r.status) && r.advice && r.advice.trim())
  if (!todo.length) return results
  const v = await agent(advicePrompt(todo), { label, phase: 'Advise', schema: ADVICE_SCHEMA, effort: 'high' })
  if (!v) { log(`advice not verified: ${todo.map(r => r.id).join(',')}`); return results }
  const by = {}
  for (const x of v.items || []) by[x.id] = x
  return results.map(r => (by[r.id]
    ? { ...r, advice: by[r.id].advice || r.advice, done: by[r.id].done, remain: by[r.id].remain, advice_ok: by[r.id].ok, advice_problem: by[r.id].problem }
    : r))
}

async function doRecheck() {
  const res = await pipeline(
    A.batches,
    (ids, _o, i) => agent(recheckPrompt(ids), { label: `recheck:${i + 1}:${ids.join(',')}`, phase: 'Recheck', schema: RECHECK_SCHEMA }),
    (r, ids, i) => adviseBatch((r && r.results) || [], `advise:${i + 1}:${ids[0]}-${ids[ids.length - 1]}`),
  )
  const flat = res.filter(Boolean).flat()
  const got = new Set(flat.map(r => r.id))
  const missing = A.batches.flat().filter(id => !got.has(id))
  if (missing.length) {
    log(`recheck missing ${missing.length}: ${missing.join(',')} — retrying`)
    const chunks = []
    for (let i = 0; i < missing.length; i += 6) chunks.push(missing.slice(i, i + 6))
    const retry = await pipeline(
      chunks,
      (ids, _o, i) => agent(recheckPrompt(ids), { label: `recheck-retry:${i + 1}`, phase: 'Recheck', schema: RECHECK_SCHEMA }),
      (r, ids, i) => adviseBatch((r && r.results) || [], `advise-retry:${i + 1}`),
    )
    flat.push(...retry.filter(Boolean).flat())
  }
  return flat
}

async function doLight() {
  const batches = A.lightBatches || []
  if (!batches.length) return []
  const res = await pipeline(batches, (ids, _o, i) => agent(lightPrompt(ids), { label: `recheck-closed:${i + 1}:${ids[0]}-${ids[ids.length - 1]}`, phase: 'Recheck', schema: RECHECK_SCHEMA }))
  const flat = res.filter(Boolean).flatMap(r => r.results)
  const got = new Set(flat.map(r => r.id))
  const missing = batches.flat().filter(id => !got.has(id))
  if (missing.length) {
    log(`closed recheck missing ${missing.length}: ${missing.join(',')} — retrying`)
    const chunks = []
    for (let i = 0; i < missing.length; i += 10) chunks.push(missing.slice(i, i + 10))
    const retry = await parallel(chunks.map((ids, i) => () => agent(lightPrompt(ids), { label: `recheck-closed-retry:${i + 1}`, phase: 'Recheck', schema: RECHECK_SCHEMA })))
    flat.push(...retry.filter(Boolean).flatMap(r => r.results))
  }
  return flat
}

async function doReview() {
  const found = await parallel(A.finders.map(f => () => agent(findPrompt(f), { label: `find:${f.key}`, phase: 'Find', schema: FIND_SCHEMA })
    .then(r => (r ? r.findings.map(x => ({ ...x, finder: f.key })) : []))))
  const cands = found.filter(Boolean).flat()
  log(`new-commit candidates: ${cands.length}`)
  const groups = {}
  for (const c of cands) { const k = groupKey(c); (groups[k] = groups[k] || []).push(c) }
  const glist = []
  for (const [k, items] of Object.entries(groups)) {
    const size = A.coarseVerify ? 8 : 6
    for (let i = 0; i < items.length; i += size) glist.push({ key: k, items: items.slice(i, i + size) })
  }
  log(`verify groups: ${glist.length}`)
  const verified = await parallel(glist.map(g => () => agent(verifyPrompt(g), { label: `verify:${g.key}`, phase: 'Verify', schema: VERIFY_SCHEMA, effort: 'high' })
    .then(r => ({ group: g, verdicts: r ? r.verdicts : null }))))
  return { cands, verified }
}

const [recheck, light, review] = await parallel([() => doRecheck(), () => doLight(), () => doReview()])
return { recheck: [...(recheck || []), ...(light || [])], review }
