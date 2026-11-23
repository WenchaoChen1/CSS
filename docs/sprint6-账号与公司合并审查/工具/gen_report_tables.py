#!/usr/bin/env python3
"""
按 findings.json 重新生成审查报告里两节由数据驱动的表格：

- 「〇-A、未关闭问题的建议解决方案」：每条未关闭的问题一行（sol 字段），按高 / 中 / 低分组；
- 「〇-C、部分修复的 N 条：修好了什么、还剩什么」：每条部分修复的问题一行（done / remain 字段）。

用法：
    python3 gen_report_tables.py --findings ../findings.json --report ../审查报告.md \
        --label '第 10 版' --backend-rev 0aafd5a6 --frontend-rev d076e5b5

报告里已有这两节时整节替换（从「## 〇-A、」或「## 〇-C、」到下一个「## 」之前）；没有时，〇-A 插在「## 〇、」这一节之后，
〇-C 插在「## 一、」之前。其余章节是手写的，不会被改动。
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

CLOSED = ('fixed', 'obsolete', 'accepted', 'waived')
SEV = {'high': '高', 'medium': '中', 'low': '低'}
SEV_FULL = {'high': '高危', 'medium': '中危', 'low': '低危'}
ORDER = {'high': 0, 'medium': 1, 'low': 2}
ST = {'new': '本版新增', 'worse': '更严重', 'still_present': '仍存在', 'partially_fixed': '部分修复'}


def key(f: dict):
    return ORDER[f['sev']], f['id'][0], int(re.sub(r'\D', '', f['id']) or 0)


def cell(s: str) -> str:
    return re.sub(r'\s+', ' ', s or '').replace('|', '\\|').strip()


def short(s: str, n: int = 44) -> str:
    s = re.sub(r'\s+', ' ', s or '').strip()
    return s if len(s) <= n else s[:n].rstrip('，、；：,; ') + '…'


def name(f: dict) -> str:
    return f"{f['id']}（{f['lab']}）" if f.get('lab') else f['id']


def replace_section(text: str, head: str, body: str, before: str) -> str:
    """把以 head 开头的二级标题那一节换成 body；没有这一节时插到以 before 开头的二级标题之前。"""
    m = re.search(r'^## ' + re.escape(head), text, re.M)
    if m:
        nxt = re.search(r'^## ', text[m.end():], re.M)
        end = m.end() + nxt.start() if nxt else len(text)
        return text[:m.start()] + body + text[end:]
    m = re.search(r'^## ' + re.escape(before), text, re.M)
    assert m, f'报告里找不到「## {before}」，无法确定插入位置'
    return text[:m.start()] + body + text[m.start():]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--findings', required=True)
    ap.add_argument('--report', required=True)
    ap.add_argument('--label', required=True, help='例如 第 10 版')
    ap.add_argument('--backend-rev', required=True)
    ap.add_argument('--frontend-rev', required=True)
    a = ap.parse_args()

    rows = json.loads(Path(a.findings).read_text(encoding='utf-8'))
    op = sorted((f for f in rows if f['st'] not in CLOSED), key=key)
    pf = [f for f in op if f['st'] == 'partially_fixed']
    base = f'后端 `{a.backend_rev}`、前端 `{a.frontend_rev}`'

    # 〇-A
    n = {s: sum(1 for f in op if f['sev'] == s) for s in ORDER}
    out = [f'## 〇-A、未关闭问题的建议解决方案（{a.label}）', '',
           f"未关闭的 {len(op)} 条问题（高危 {n['high']}、中危 {n['medium']}、低危 {n['low']}）每条都给了建议的改法，按{base}的代码写，"
           '并由另一个审查代理独立复核过：是否对症、在现有代码里是否可行、是否和已确认的决定冲突（已推送的迁移不原地修改、`deprecated_` 表视为不存在等）。'
           '这是建议，不是唯一做法；写明「需要先决定」的，要先由产品或你确认。页面「全部问题」表里，每条未关闭的问题下面也直接显示这一段。', '']
    missing = [f['id'] for f in op if not f.get('sol')]
    for s in ORDER:
        part = [f for f in op if f['sev'] == s]
        if not part:
            continue
        out += [f'### {SEV_FULL[s]}（{len(part)} 条）', '', '| 条目 | 状态 | 问题 | 建议解决方案 |', '|---|---|---|---|']
        out += [f"| {name(f)} | {ST.get(f['st'], f['st'])} | {cell(short(f['text']))} | {cell(f.get('sol') or '（待补）')} |" for f in part]
        out.append('')
    sec_a = '\n'.join(out) + '\n---\n\n'

    # 〇-C
    m = {s: sum(1 for f in pf if f['sev'] == s) for s in ORDER}
    out = [f'## 〇-C、部分修复的 {len(pf)} 条：修好了什么、还剩什么', '',
           f"「部分修复」表示问题的一部分已经修好，另一部分还在。下表逐条写明两部分（高危 {m['high']}、中危 {m['medium']}、低危 {m['low']}），"
           f'{a.label}按{base}重新核对，「还剩」只写仍然存在的部分；怎么改见「〇-A」。页面「全部问题」表里，这些条目下面也直接显示这两行；详细证据见各条的复核说明。', '',
           '| 条目 | 级别 | 问题 | 已修好 | 还剩 |', '|---|---|---|---|---|']
    out += [f"| {name(f)} | {SEV[f['sev']]} | {cell(short(f['text'], 40))} | {cell(f.get('done') or '（待补）')} | {cell(f.get('remain') or '（待补）')} |" for f in pf]
    sec_c = '\n'.join(out) + '\n\n---\n\n'

    p = Path(a.report)
    text = p.read_text(encoding='utf-8')
    # 〇-A 紧跟在「〇、本次复核结论」之后：也就是插在它后面的第一个二级标题之前
    if not re.search(r'^## 〇-A、', text, re.M):
        m0 = re.search(r'^## 〇、', text, re.M)
        assert m0, '报告里找不到「## 〇、」'
        nxt = re.search(r'^## ', text[m0.end():], re.M)
        pos = m0.end() + nxt.start()
        text = text[:pos] + sec_a + text[pos:]
    else:
        text = replace_section(text, '〇-A、', sec_a, '一、')
    text = replace_section(text, '〇-C、', sec_c, '一、')
    p.write_text(text, encoding='utf-8')
    print(f'〇-A {len(op)} 条（缺建议：{missing}）；〇-C {len(pf)} 条（缺 done/remain：'
          f"{[f['id'] for f in pf if not (f.get('done') and f.get('remain'))]}）")


if __name__ == '__main__':
    main()
