#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Check the BUILT docs site (_site/, from tools/build_docs_site.py) for what a
reader of the published pages would hit, and tools/doclinks.py cannot see.

doclinks.py checks EXTERNAL links. This checks everything internal, on the
rendered HTML rather than the Markdown, because the renderer is where links
break: it rewrites only `*.md` links to `.html`, so a link that works when
GitHub renders the .md (a directory, a file outside docs/) can be dead on the
site.

  links    every relative href/src resolves to a file in the site
  anchors  every #fragment names an id on the target page
  alt      every <img> has non-empty alt text
  leaks    Markdown that did not render: a table row, a fence, a heading
           marker or ** emphasis in running text, or a double-escaped entity
  nav      every page is reachable from the sidebar

Usage:  tools/docsite_check.py [--build] [--site _site] [-v]
Exit 1 when anything is found. Each finding names the SOURCE .md and the
target as written, so it can be fixed where it lives.
"""

import argparse
import html
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent


class Page(HTMLParser):
    """Collects ids, links, images and the text outside <pre>/<code>."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids, self.links, self.imgs, self.nav = set(), [], [], []
        self.text, self._code, self._in_nav, self._in_main = [], 0, 0, 0

    BLOCKS = {'p', 'li', 'td', 'th', 'tr', 'div', 'blockquote', 'br',
              'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag in self.BLOCKS:
            self.text.append('\n')      # a leak pattern is anchored to a line
        if a.get('id'):
            self.ids.add(a['id'])
        if tag in ('pre', 'code'):
            self._code += 1
        if tag == 'nav':
            self._in_nav += 1
        if tag == 'main':
            self._in_main += 1
        if tag == 'a' and a.get('href') is not None:
            (self.nav if self._in_nav else self.links).append(a['href'])
        if tag == 'img':
            self.imgs.append((a.get('src', ''), a.get('alt', '')))
            if a.get('src'):
                self.links.append(a['src'])

    def handle_endtag(self, tag):
        if tag in ('pre', 'code') and self._code:
            self._code -= 1
        if tag == 'nav' and self._in_nav:
            self._in_nav -= 1
        if tag == 'main' and self._in_main:
            self._in_main -= 1

    def handle_data(self, data):
        if self._in_main and not self._code:
            self.text.append(data)


# Markdown that survived rendering, in text outside code. Each is anchored so
# that ordinary prose ("a | b" in a sentence, "2 ** 3") does not match.
LEAKS = [
    ('table row', re.compile(r'^\s*\|.*\|\s*$', re.M)),
    ('table rule', re.compile(r'^\s*\|?\s*:?-{3,}:?\s*\|', re.M)),
    ('code fence', re.compile(r'^\s*(```|~~~)', re.M)),
    ('heading marker', re.compile(r'^#{1,6} \S', re.M)),
    ('bold marker', re.compile(r'(?<![\w*])\*\*[A-Za-z][^*\n]{0,80}\*\*(?![\w*])')),
    ('link syntax', re.compile(r'\]\((\.\.?/|https?://)[^)\s]*\)')),
    ('escaped entity', re.compile(r'&(amp|lt|gt|quot);')),
]


def source_of(site, page):
    rel = page.relative_to(site).with_suffix('.md')
    return 'docs/' + rel.as_posix()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--site', default=str(ROOT / '_site'))
    ap.add_argument('--build', action='store_true', help='run tools/build_docs_site.py first')
    ap.add_argument('-v', action='store_true')
    args = ap.parse_args()

    if args.build:
        subprocess.run([sys.executable, str(ROOT / 'tools' / 'build_docs_site.py')], check=True)
    site = Path(args.site).resolve()
    pages = sorted(site.rglob('*.html'))
    if not pages:
        sys.exit(f'docsite_check: no pages under {site} (build first, or pass --build)')

    parsed = {}
    for p in pages:
        pp = Page()
        pp.feed(p.read_text(encoding='utf-8'))
        parsed[p] = pp

    findings = []

    def add(kind, page, detail):
        findings.append((kind, source_of(site, page), detail))

    reached = set()
    for p, pp in parsed.items():
        for href in pp.nav:
            u = urlsplit(href)
            if not u.scheme and u.path:
                reached.add((p.parent / unquote(u.path)).resolve())
        for href in pp.links:
            u = urlsplit(href)
            if u.scheme or href.startswith('//') or href.startswith('mailto:'):
                continue
            target = p if not u.path else (p.parent / unquote(u.path)).resolve()
            if target.is_dir():
                target = target / 'index.html'
            if not target.exists():
                add('link', p, href)
                continue
            if u.fragment and target.suffix == '.html':
                tp = parsed.get(target)
                if tp is not None and unquote(u.fragment) not in tp.ids:
                    add('anchor', p, href)
        for src, alt in pp.imgs:
            if not alt.strip():
                add('alt', p, src)
        text = ''.join(pp.text)
        for name, rx in LEAKS:
            for m in rx.finditer(text):
                # the text that follows tells two leaks of the same shape apart
                what = text[m.start():m.start() + 60].strip().replace('\n', ' ')
                add('leak', p, f'{name}: {what!r}')

    for p in pages:
        if p.resolve() not in reached and p.relative_to(site).as_posix() != 'index.html':
            add('nav', p, 'not linked from the sidebar')

    for kind, src, detail in sorted(set(findings)):
        print(f'{kind:7s} {src}: {detail}')
    counts = {}
    for kind, _, _ in set(findings):
        counts[kind] = counts.get(kind, 0) + 1
    summary = ', '.join(f'{k} {v}' for k, v in sorted(counts.items())) or 'clean'
    print(f'docsite_check: {len(pages)} pages; {summary}')
    sys.exit(1 if findings else 0)


if __name__ == '__main__':
    main()
