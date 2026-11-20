export const meta = {
  name: 'sprint6-merge-review-recheck',
  description: 'Re-verify the sprint6 account/company merge review findings against the latest code and review the new commits',
  whenToUse: 'Run from 提示词/sprint6合并审查.md (or /sprint6-merge-review) once sprint/sprint6 has moved past the baseline recorded in findings.json',
  phases: [
    { title: 'Recheck', detail: 'every finding of the previous round against HEAD, in batches' },
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
        },
        required: ['id', 'status', 'changed_since_prev', 'fixed_by', 'severity_now', 'evidence', 'note', 'reply_verdict', 'reply_check'],
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
${A.repliesPath ? REPLY_RULES : '6. reply_verdict 填 none，reply_check 填空字符串。'}`
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
  const f = (c.file || '').split(/[,，、（ ]/)[0]
  if (f.includes('migrations/versions')) return c.repo + ':migrations'
  const parts = f.split('/').filter(Boolean)
  return c.repo + ':' + parts.slice(0, Math.min(parts.length - 1, 5)).join('/')
}

async function doRecheck() {
  const res = await pipeline(A.batches, (ids, _o, i) => agent(recheckPrompt(ids), { label: `recheck:${i + 1}:${ids.join(',')}`, phase: 'Recheck', schema: RECHECK_SCHEMA }))
  const flat = res.filter(Boolean).flatMap(r => r.results)
  const got = new Set(flat.map(r => r.id))
  const missing = A.batches.flat().filter(id => !got.has(id))
  if (missing.length) {
    log(`recheck missing ${missing.length}: ${missing.join(',')} — retrying`)
    const chunks = []
    for (let i = 0; i < missing.length; i += 6) chunks.push(missing.slice(i, i + 6))
    const retry = await parallel(chunks.map((ids, i) => () => agent(recheckPrompt(ids), { label: `recheck-retry:${i + 1}`, phase: 'Recheck', schema: RECHECK_SCHEMA })))
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
    for (let i = 0; i < items.length; i += 6) glist.push({ key: k, items: items.slice(i, i + 6) })
  }
  log(`verify groups: ${glist.length}`)
  const verified = await parallel(glist.map(g => () => agent(verifyPrompt(g), { label: `verify:${g.key}`, phase: 'Verify', schema: VERIFY_SCHEMA, effort: 'high' })
    .then(r => ({ group: g, verdicts: r ? r.verdicts : null }))))
  return { cands, verified }
}

const [recheck, review] = await parallel([() => doRecheck(), () => doReview()])
return { recheck, review }
