#!/usr/bin/env python3
"""
把一批团队书面答复和它们的核实结论写进 findings.json（在 apply_recheck.py / apply_delta.py 之后运行）。

用法：
    python3 apply_replies.py \
        --findings ../findings.json \
        --result   <scratchpad>/wf_result.json \
        --replies  <scratchpad>/replies.json \
        --batch    4 \
        --keep-open N2,N99,N101,N102,N103 \
        --backend  /path/to/CSS_backend-main \
        --out      ../findings.json

输入：
- replies.json：{id: [{seg, text}]}，同一条可以有几段答复（recheck-workflow.js 的 repliesPath 用的就是它）。
- wf_result.json：recheck-workflow.js 的返回值；recheck 里每条有 reply_verdict / reply_check（D19）。
  也可以带 overrides：{"reply_overrides": {"N129": {"verdict": "not_hold", "check": "人工核对后的说明"}}}，
  写在 --result 同目录的 reply_overrides.json 里，用 --overrides 传入。

脚本会：
- 把答复原话写进 reply（几段答复按「（第 1 段）…（第 2 段）…」拼起来）、批次写进 replyb、核实结论写进 replyv
  （「成立：…」「部分成立：…」「不成立：…」「按设计接受：…」「按前提不计入：…」）；
- 条目以前已有别的批次的答复时，把旧的原话和核实接到说明末尾，以「（以下为第 N 批团队答复的核实，保留）」开头，
  apply_recheck.py 下一版会自动把它带过去；
- 按 D19 处理状态：按设计接受 → accepted，按前提不计入 → waived（都会去掉 sol / done / remain）；
  --keep-open 里的条目（例如 D23 用户已决定不接受的、D6 写明仍按风险跟踪的）状态不变，只更新答复；
  成立 / 部分成立 / 不成立按复核给出的状态，不在这里改；
- 打印每类结论的条目，供写报告用。
"""
from __future__ import annotations

import argparse
import collections
import json
import re
from pathlib import Path

CLOSED = ('fixed', 'obsolete', 'accepted', 'waived')
LABEL = {'holds': '成立', 'partly': '部分成立', 'not_hold': '不成立', 'design_accept': '按设计接受',
         'premise_waive': '按前提不计入'}


def load_secret(backend: Path) -> str | None:
    hits = list(backend.glob('core_app/src/app/migrations/versions/*4b52dd3297e5*.py'))
    if not hits:
        return None
    m = re.search(r"^PASSWORD\s*=\s*['\"]([^'\"]+)['\"]", hits[0].read_text(encoding='utf-8'), re.M)
    return m.group(1) if m else None


def main() -> None:
    ap = argparse.ArgumentParser()
    for k in ('findings', 'result', 'replies', 'batch', 'backend', 'out'):
        ap.add_argument('--' + k, required=True)
    ap.add_argument('--keep-open', default='', help='逗号分隔：按设计接受也不关闭的条目')
    ap.add_argument('--overrides', help='人工改判：{"reply_overrides": {id: {verdict, check}}}')
    a = ap.parse_args()

    secret = load_secret(Path(a.backend))
    secrets = [s for s in {secret, (secret or '').rstrip('!')} if s]

    def mask(s: str | None) -> str:
        s = s or ''
        for x in sorted(secrets, key=len, reverse=True):
            s = s.replace(x, '<固定密码>')
        return s

    rows = json.loads(Path(a.findings).read_text(encoding='utf-8'))
    res = json.loads(Path(a.result).read_text(encoding='utf-8'))
    rc = {x['id']: x for x in res['recheck']}
    replies = json.loads(Path(a.replies).read_text(encoding='utf-8'))
    ov = json.loads(Path(a.overrides).read_text(encoding='utf-8')).get('reply_overrides', {}) if a.overrides else {}
    keep_open = {x.strip() for x in a.keep_open.split(',') if x.strip()}
    batch = int(a.batch)

    by_verdict = collections.defaultdict(list)
    closed_now, kept = [], []
    missing = [i for i in replies if i not in rc and i not in ov]
    assert not missing, f'复核结果里没有这些答复过的条目：{missing}'
    for f in rows:
        segs = replies.get(f['id'])
        if not segs:
            continue
        x = rc.get(f['id'], {})
        o = ov.get(f['id'], {})
        verdict = o.get('verdict') or x.get('reply_verdict') or 'none'
        check = mask(o.get('check') or x.get('reply_check') or '')
        assert verdict in LABEL, (f['id'], verdict)
        texts = [s['text'].strip() for s in segs]
        if len(texts) > 1:
            said = ''.join(f'（第 {i + 1} 段）{t}' for i, t in enumerate(texts))
        else:
            said = texts[0]
        if f.get('reply') and f.get('replyb') != batch:
            f['note'] = (f['note'].rstrip('\n') + f"\n（以下为第 {f.get('replyb')} 批团队答复的核实，保留）团队答复：{f['reply']}\n"
                         f"核实：{f.get('replyv', '')}")
        f['reply'], f['replyb'], f['replyv'] = said, batch, f'{LABEL[verdict]}：{check}'
        by_verdict[verdict].append(f['id'])
        if verdict in ('design_accept', 'premise_waive') and f['st'] not in CLOSED:
            if f['id'] in keep_open:
                kept.append(f['id'])
                continue
            # prev / psev 已由 apply_recheck.py 设成上一版的值，这里只改本版状态
            f['st'] = 'accepted' if verdict == 'design_accept' else 'waived'
            f['chg'] = True
            for k in ('sol', 'done', 'remain'):
                f.pop(k, None)
            closed_now.append(f['id'])

    text = json.dumps(rows, ensure_ascii=False, indent=1)
    for s in secrets:
        assert s not in text, '输出里仍有固定密码原文'
    Path(a.out).write_text(text, encoding='utf-8')

    for v in LABEL:
        print(f'{LABEL[v]}（{len(by_verdict[v])}）：', '、'.join(by_verdict[v]))
    print('按答复关闭：', '、'.join(closed_now))
    print('按设计接受 / 按前提不计入但保持未关闭（--keep-open）：', '、'.join(kept))
    op = [r for r in rows if r['st'] not in CLOSED]
    print('未关闭', len(op), dict(collections.Counter(r['sev'] for r in op)))


if __name__ == '__main__':
    main()
