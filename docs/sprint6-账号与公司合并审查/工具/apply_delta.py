#!/usr/bin/env python3
"""
同一版复核中途代码又前进时，把「增量复核」的结果叠加到中间稿上，生成本版最终的问题清单。

一版复核通常是：apply_recheck.py 把 Workflow 结果合进 findings.json。如果复核途中 sprint6 又有新提交，
先把第一段结果写成中间稿（apply_recheck.py --out <中间稿>），拉到最新代码后用同一个 recheck-workflow.js
跑增量（findingsPath 指向中间稿，baseBe/baseFe 用第一段的 HEAD），再用本脚本叠加：

    python3 apply_delta.py \
        --findings <scratchpad>/findings_mid.json \
        --result   <scratchpad>/wf_result_delta.json \
        --decisions <scratchpad>/decisions_delta.json \
        --backend  /path/to/CSS_backend-main \
        --label    '增量复核（后端 4b1db16c、前端 bc820add）' \
        --out      ../findings.json

与 apply_recheck.py 的区别：
- prev / psev 保持中间稿里的值（即上一版的状态），这样报告里的「状态变化」仍是相对上一版；
- 说明不覆盖，在中间稿说明后面追加「<label>：…」；
- 中间稿里 st=new 的条目（本版新发现）增量后仍存在时保持 new，被后续提交修好时改为 fixed；
- decisions 格式与 apply_recheck.py 相同（overrides / new / merged / rejected），新编号接着中间稿最大的 N 号。
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

CLOSED = ('fixed', 'obsolete', 'accepted', 'waived')
KEEP = ('accepted', 'waived')


def load_secret(backend: Path) -> str | None:
    hits = list(backend.glob('core_app/src/app/migrations/versions/*4b52dd3297e5*.py'))
    if not hits:
        return None
    m = re.search(r"^PASSWORD\s*=\s*['\"]([^'\"]+)['\"]", hits[0].read_text(encoding='utf-8'), re.M)
    return m.group(1) if m else None


def main() -> None:
    ap = argparse.ArgumentParser()
    for k in ('findings', 'result', 'decisions', 'backend', 'label', 'out'):
        ap.add_argument('--' + k, required=True)
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

    missing = [r['id'] for r in rows if r['id'] not in rc and r['st'] not in KEEP and r['id'] not in ov]
    if missing:
        sys.exit(f'增量结果里缺少这些 id：{missing}')

    out = []
    for f in rows:
        x = rc.get(f['id'])
        o = ov.get(f['id'], {})
        r = dict(f)
        if x is not None or o:
            x = x or {'status': f['st'], 'severity_now': f['sev'], 'note': '', 'evidence': '', 'fixed_by': [],
                      'changed_since_prev': False}
            st = x['status']
            if f['st'] in KEEP:
                st = f['st']
            elif f['st'] == 'new' and st not in CLOSED:
                st = 'new'
            st = o.get('st', st)
            sev = o.get('sev', x['severity_now'])
            if st in CLOSED or sev == 'none':
                sev = f['sev']
            add = o.get('note', mask(x['note']) + o.get('append', ''))
            if st not in CLOSED and x.get('evidence'):
                add += '\n证据：' + mask(x['evidence'])
            r['note'] = mask(f['note']) + f'\n{a.label}：' + add
            fixes = [h for h in (f.get('fix', '').split() + (o.get('fix', '').split() or x.get('fixed_by') or [])) if h]
            r['fix'] = ' '.join(dict.fromkeys(fixes))
            r['st'], r['sev'] = st, sev
            r['chg'] = bool(f.get('chg')) or bool(x.get('changed_since_prev')) or bool(o) or st != f['st']
        out.append(r)

    seen = set()
    existing = {r['id'] for r in out}
    for n in dec.get('new', []):
        assert n['id'] not in existing, f"新编号 {n['id']} 已被占用"
        vs, its = [], []
        for gi, idx in n['refs']:
            assert (gi, idx) not in seen, f'候选 {gi},{idx} 被重复引用'
            seen.add((gi, idx))
            vs.append([v for v in ver[gi]['verdicts'] if v['idx'] == idx][0])
            its.append(ver[gi]['group']['items'][idx])
        main_v = next(v for v in vs if v['verdict'] == 'confirmed')
        main_i = its[vs.index(main_v)]
        note = f'{a.label}发现：' + mask(main_v['detail']) + '\n证据：' + mask(main_v['evidence'])
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
        existing.add(n['id'])

    merged = {tuple(int(p) for p in k.split(',')) for k in dec.get('merged', {})}
    rejected = {tuple(int(p) for p in k.split(',')) for k in dec.get('rejected', [])}
    allv = [(gi, v['idx']) for gi, g in enumerate(ver) for v in (g['verdicts'] or [])]
    left = [k for k in allv if k not in seen and k not in merged and k not in rejected]
    if left:
        sys.exit(f'这些候选还没有归入 new / merged / rejected：{left}')

    def nkey(r: dict) -> tuple:
        return (r['id'][0] != 'F', int(re.sub(r'\D', '', r['id']) or 0))

    old = [r for r in out if r['prev'] != '']
    new = sorted([r for r in out if r['prev'] == ''], key=nkey)
    out = old + new
    text = json.dumps(out, ensure_ascii=False, indent=1)
    for s in secrets:
        assert s not in text, '输出里仍有固定密码原文'
    Path(a.out).write_text(text, encoding='utf-8')

    op = [r for r in out if r['st'] not in CLOSED]
    print('总数', len(out), '未关闭', len(op), dict(collections.Counter(r['sev'] for r in op)))
    print('本版新增（含中间稿）', dict(collections.Counter(r['sev'] for r in new)),
          '其中已关闭', [r['id'] for r in new if r['st'] in CLOSED])
    print('已有问题状态', dict(collections.Counter(r['st'] for r in old)))
    print('相对上一版的状态变化', dict(collections.Counter((r['prev'], r['st']) for r in old if r['prev'] != r['st'])))
    print('相对上一版的级别变化', [(r['id'], r['lab'], r['psev'], r['sev']) for r in old
                           if r['st'] not in CLOSED and r['psev'] and r['psev'] != r['sev']])
    mid = {f['id']: f for f in rows}
    print('增量中改变状态的条目', [(r['id'], mid[r['id']]['st'], r['st']) for r in out
                          if r['id'] in mid and mid[r['id']]['st'] != r['st']])
    print('增量中改变级别的条目', [(r['id'], mid[r['id']]['sev'], r['sev']) for r in out
                          if r['id'] in mid and mid[r['id']]['sev'] != r['sev']])
    print('未关闭高危', [(r['id'], r['lab'], r['st']) for r in op if r['sev'] == 'high'])


if __name__ == '__main__':
    main()
