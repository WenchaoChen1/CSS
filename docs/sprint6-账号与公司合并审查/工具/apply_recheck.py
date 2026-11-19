#!/usr/bin/env python3
"""
把一轮复核的 Workflow 结果合并进 findings.json，生成下一版问题清单。

用法：
    python3 apply_recheck.py \
        --findings ../findings.json \
        --result   <scratchpad>/wf_result.json \
        --decisions <scratchpad>/decisions.json \
        --backend  /path/to/CSS_backend-main \
        --out      ../findings.json

输入：
- findings.json：上一版的问题清单（字段说明见 ../README.md）。
- wf_result.json：recheck-workflow.js 的返回值 {recheck: [...], review: {cands, verified}}。
- decisions.json：本轮人工裁定，格式：
    {
      "overrides": {"F11": {"st": "still_present", "sev": "low", "append": " 第 5 版：……", "note": "整段替换说明", "fix": "abc12345"}},
      "new": [{"id": "N88", "sev": "medium", "refs": [[0, 1], [3, 2]], "title": "……",
               "hash": "可选，默认取候选里的 8 位提交", "by": "可选，默认按作者名推断", "sev_note": "可选，附在说明末尾"}],
      "merged": {"1,1": "N37"},        # 并入已有问题的候选，键为 "组号,idx"
      "rejected": ["2,1"],              # 驳回的候选
      "authors": ["Felix", "Lily", "lucy"]
    }
  refs 里的 [组号, idx] 指 review.verified[组号].group.items[idx]，idx 从 0 开始；同一条新问题合并多条候选时，
  以第一条 verdict 为 confirmed 的候选为主。

脚本会：
- 用 recheck 结果更新每条已有问题的 st / sev / note / fix，并把上一版的 sev / st 存到 psev / prev；
- 按 decisions.new 生成新问题（st=new）；
- 检查每条候选都被归入 new / merged / rejected，有遗漏就报错；
- 把迁移 4b52dd3297e5 里的固定密码替换成 <固定密码>，并确认输出里不含原文；
- 打印统计数字，供写报告用。
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

CLOSED = ('fixed', 'obsolete', 'accepted', 'waived')
KEEP = ('accepted', 'waived')  # 用户已确认的处理，复核结果不覆盖，只有 overrides 里写了 st 才改


def load_secret(backend: Path) -> str | None:
    """固定密码只从迁移文件里读，不写进任何会提交的文件。"""
    hits = list(backend.glob('core_app/src/app/migrations/versions/*4b52dd3297e5*.py'))
    if not hits:
        return None
    m = re.search(r"^PASSWORD\s*=\s*['\"]([^'\"]+)['\"]", hits[0].read_text(encoding='utf-8'), re.M)
    return m.group(1) if m else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--findings', required=True)
    ap.add_argument('--result', required=True)
    ap.add_argument('--decisions', required=True)
    ap.add_argument('--backend', required=True)
    ap.add_argument('--out', required=True)
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
    dec = json.loads(Path(a.decisions).read_text(encoding='utf-8'))
    rc = {x['id']: x for x in res['recheck']}
    ver = res['review']['verified']
    ov = dec.get('overrides', {})
    authors = dec.get('authors', ['Felix', 'Lily', 'lucy'])

    out = []
    missing = []
    for f in rows:
        x = rc.get(f['id'])
        o = ov.get(f['id'], {})
        if x is None:
            if f['st'] in KEEP or o:
                x = {'status': f['st'], 'severity_now': f['sev'], 'note': f['note'], 'evidence': '', 'fixed_by': [],
                     'changed_since_prev': False}
            else:
                missing.append(f['id'])
                continue
        st = o.get('st', f['st'] if f['st'] in KEEP else x['status'])
        sev = o.get('sev', x['severity_now'])
        if st in CLOSED or sev == 'none':
            sev = f['sev']
        note = o.get('note', mask(x['note']) + o.get('append', ''))
        if st not in CLOSED and x.get('evidence'):
            note += '\n证据：' + mask(x['evidence'])
        fix = o.get('fix', ' '.join(x.get('fixed_by') or []))
        out.append(dict(
            id=f['id'], lab=f.get('lab', ''), sev=sev, psev=f['sev'], orig=f.get('orig', f['sev']), st=st,
            prev=f['st'], text=mask(f['text']), hash=f.get('hash', ''), file=f.get('file', ''), note=mask(note),
            fix=fix, by=f.get('by', ''),
            chg=bool(x.get('changed_since_prev')) or f['id'] in ov or st != f['st'],
            # 团队答复（原话、批次、一句话核实结论）原样保留到下一版
            **{k: f[k] for k in ('reply', 'replyb', 'replyv') if k in f},
            # 部分修复的「已修好 / 还剩」只在状态没变时带过去；每版复核后应按新代码重写
            **({k: f[k] for k in ('done', 'remain') if k in f} if st == f['st'] == 'partially_fixed' else {}),
        ))
    if missing:
        sys.exit(f'recheck 结果里缺少这些 id：{missing}')

    seen = set()
    existing_ids = {r['id'] for r in out}
    for n in dec.get('new', []):
        assert n['id'] not in existing_ids, f"新编号 {n['id']} 已被占用"
        vs, its = [], []
        for gi, idx in n['refs']:
            assert (gi, idx) not in seen, f'候选 {gi},{idx} 被重复引用'
            seen.add((gi, idx))
            vs.append([v for v in ver[gi]['verdicts'] if v['idx'] == idx][0])
            its.append(ver[gi]['group']['items'][idx])
        main_v = next(v for v in vs if v['verdict'] == 'confirmed')
        main_i = its[vs.index(main_v)]
        note = mask(main_v['detail']) + '\n证据：' + mask(main_v['evidence'])
        if len(n['refs']) > 1:
            note += f"\n（{len(n['refs'])} 条候选合并为一条）"
        if n.get('sev_note'):
            note += '\n' + n['sev_note']
        astr = ' '.join(it.get('author', '') for it in its)
        by = n.get('by') or '、'.join(x for x in authors if x in astr)
        hs = []
        for it in [main_i] + its:
            for h in re.findall(r'\b[0-9a-f]{8}\b', it.get('commit', '')):
                if h not in hs:
                    hs.append(h)
        out.append(dict(
            id=n['id'], lab='', sev=n['sev'], psev='', orig=n['sev'], st='new', prev='', text=n['title'],
            hash=n.get('hash') or ' '.join(hs[:4]), file=re.split(r'[；;]', main_i.get('file') or '')[0],
            note=mask(note), fix='', by=by, chg=True,
        ))
        existing_ids.add(n['id'])

    merged = {tuple(int(p) for p in k.split(',')) for k in dec.get('merged', {})}
    rejected = {tuple(int(p) for p in k.split(',')) for k in dec.get('rejected', [])}
    allv = [(gi, v['idx']) for gi, g in enumerate(ver) for v in (g['verdicts'] or [])]
    left = [k for k in allv if k not in seen and k not in merged and k not in rejected]
    if left:
        sys.exit(f'这些候选还没有归入 new / merged / rejected：{left}')

    old = [r for r in out if r['st'] != 'new']
    new = sorted([r for r in out if r['st'] == 'new'], key=lambda r: int(re.sub(r'\D', '', r['id']) or 0))
    out = old + new
    text = json.dumps(out, ensure_ascii=False, indent=1)
    for s in secrets:
        assert s not in text, '输出里仍有固定密码原文'
    Path(a.out).write_text(text, encoding='utf-8')

    op = [r for r in out if r['st'] not in CLOSED]
    print('总数', len(out), '未关闭', len(op), dict(collections.Counter(r['sev'] for r in op)))
    print('本版新增', dict(collections.Counter(r['sev'] for r in new)))
    print('已有问题状态', dict(collections.Counter(r['st'] for r in old)))
    print('状态变化', dict(collections.Counter((r['prev'], r['st']) for r in old if r['prev'] != r['st'])))
    print('级别变化', [(r['id'], r['lab'], r['psev'], r['sev']) for r in old if r['st'] not in CLOSED and r['psev'] != r['sev']])
    print('未关闭高危', [(r['id'], r['lab'], r['st']) for r in op if r['sev'] == 'high'])


if __name__ == '__main__':
    main()
