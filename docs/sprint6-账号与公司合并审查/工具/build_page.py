#!/usr/bin/env python3
"""
用 page-template.html + findings.json 生成报告页面。

用法：
    python3 build_page.py --findings ../findings.json --template page-template.html \
        --backend /path/to/CSS_backend-main --out ../审查报告.html [--standalone]

- 模板里的 __DATA__ 会被替换成 findings.json 的内容；页面里「全部问题」表格、筛选和搜索都由它驱动。
- 模板里手写的部分（结论、数字、高危卡片、中低危分类、建议）每一版都要按报告人工更新。
- --standalone：在开头补上 <!doctype html> 和 UTF-8 声明，便于直接用浏览器打开本地文件；
  发布到 claude.ai Artifact 时不加（发布时会自动包一层文档骨架）。
- 生成后会检查页面里不含迁移 4b52dd3297e5 中的固定密码原文。
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def load_secret(backend: Path) -> str | None:
    hits = list(backend.glob('core_app/src/app/migrations/versions/*4b52dd3297e5*.py'))
    if not hits:
        return None
    m = re.search(r"^PASSWORD\s*=\s*['\"]([^'\"]+)['\"]", hits[0].read_text(), re.M)
    return m.group(1) if m else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--findings', required=True)
    ap.add_argument('--template', required=True)
    ap.add_argument('--backend', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--standalone', action='store_true')
    a = ap.parse_args()

    rows = json.loads(Path(a.findings).read_text())
    data = json.dumps(rows, ensure_ascii=False).replace('</', '<\\/')
    tpl = Path(a.template).read_text()
    assert tpl.count('__DATA__') == 1, '模板里应当恰好有一个 __DATA__'
    page = tpl.replace('__DATA__', data)
    if a.standalone:
        page = '<!doctype html>\n<meta charset="utf-8">\n' + page
    secret = load_secret(Path(a.backend))
    for s in [secret, (secret or '').rstrip('!')]:
        if s:
            assert s not in page, '页面里出现了固定密码原文'
    Path(a.out).write_text(page)
    print(f'{a.out}: {len(page.encode())} bytes, {len(rows)} rows')


if __name__ == '__main__':
    main()
