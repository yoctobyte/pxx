#!/usr/bin/env python3
"""Build the static docs website from docs/**/*.md into _site/.

No framework, no content-model lock-in: reads the existing docs/ topic-folder
+ index.md + `order:` front matter convention directly, converts each page
with python-markdown, and wraps it in one shared template. Internal .md links
are rewritten to .html; everything else in the docs/ tree is left untouched.
"""
import re
import shutil
import sys
from pathlib import Path

import markdown

DOCS = Path(__file__).resolve().parent.parent / "docs"
OUT = Path(__file__).resolve().parent.parent / "_site"

FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n(.*)\Z", re.DOTALL)
MD_LINK_RE = re.compile(r'href="([^"]+?)\.md(#[^"]*)?"')

TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · PXX docs</title>
<link rel="stylesheet" href="{prefix}assets/style.css">
</head>
<body>
<header class="site-header"><a href="{home_href}">PXX docs</a></header>
<div class="layout">
<nav class="sidebar">
{nav}
</nav>
<main>
{content}
</main>
</div>
</body>
</html>
"""

CSS = """
* { box-sizing: border-box; }
body { margin: 0; font: 16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; color: #1a1a1a; }
.site-header { padding: .75rem 1.25rem; border-bottom: 1px solid #ddd; font-weight: 600; }
.site-header a { color: inherit; text-decoration: none; }
.layout { display: flex; align-items: flex-start; max-width: 78rem; margin: 0 auto; }
.sidebar { flex: 0 0 16rem; padding: 1.25rem 1rem; position: sticky; top: 0; max-height: 100vh; overflow-y: auto; }
.sidebar ul { list-style: none; margin: 0; padding: 0 0 0 .75rem; }
.sidebar > ul { padding-left: 0; }
.sidebar li { margin: .15rem 0; }
.sidebar a { color: #333; text-decoration: none; }
.sidebar a.active { color: #a4373a; font-weight: 600; }
.sidebar a:hover { text-decoration: underline; }
main { flex: 1 1 auto; padding: 1.25rem 1.5rem 4rem; min-width: 0; }
main pre { background: #f6f6f6; padding: .75rem 1rem; overflow-x: auto; border-radius: 4px; }
main code { background: #f0f0f0; padding: .1rem .3rem; border-radius: 3px; }
main pre code { background: none; padding: 0; }
main table { border-collapse: collapse; }
main th, main td { border: 1px solid #ddd; padding: .35rem .6rem; }
main blockquote { border-left: 3px solid #a4373a; margin-left: 0; padding-left: 1rem; color: #555; }
"""


def parse_frontmatter(text):
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta, m.group(2)


def collect_pages():
    pages = []
    for path in sorted(DOCS.rglob("*.md")):
        rel = path.relative_to(DOCS)
        meta, body = parse_frontmatter(path.read_text())
        pages.append(
            {
                "rel": rel,
                "meta": meta,
                "body": body,
                "is_index": rel.name == "index.md",
                "section": rel.parts[0] if len(rel.parts) > 1 else None,
                "order": int(meta.get("order", 0)),
                "title": meta.get("title", rel.stem),
            }
        )
    return pages


def build_nav(pages):
    sections = sorted(
        (p for p in pages if p["is_index"] and p["rel"] != Path("index.md")),
        key=lambda p: p["order"],
    )
    nav = []
    for sec in sections:
        sec_dir = sec["rel"].parts[0]
        children = sorted(
            (p for p in pages if p["section"] == sec_dir and not p["is_index"]),
            key=lambda p: p["order"],
        )
        nav.append((sec, children))
    return nav


def render_nav(nav, current_rel, prefix):
    def link(page):
        href = prefix + str(page["rel"].with_suffix(".html")).replace("\\", "/")
        cls = ' class="active"' if page["rel"] == current_rel else ""
        return f'<a href="{href}"{cls}>{page["title"]}</a>'

    out = ["<ul>", f'<li>{link({"rel": Path("index.md"), "title": "Home"})}</li>']
    for sec, children in nav:
        out.append(f"<li>{link(sec)}")
        if children:
            out.append("<ul>")
            for child in children:
                out.append(f"<li>{link(child)}</li>")
            out.append("</ul>")
        out.append("</li>")
    out.append("</ul>")
    return "\n".join(out)


def rewrite_links(html_text):
    return MD_LINK_RE.sub(lambda m: f'href="{m.group(1)}.html{m.group(2) or ""}"', html_text)


def main():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "assets").mkdir()
    (OUT / "assets" / "style.css").write_text(CSS)

    pages = collect_pages()
    nav = build_nav(pages)

    for page in pages:
        depth = len(page["rel"].parts) - 1
        prefix = "../" * depth
        body_html = markdown.markdown(page["body"], extensions=["fenced_code", "tables"])
        body_html = rewrite_links(body_html)
        nav_html = render_nav(nav, page["rel"], prefix)
        html_out = TEMPLATE.format(
            title=page["title"], prefix=prefix, home_href=prefix or ".", nav=nav_html, content=body_html
        )
        dest = OUT / page["rel"].with_suffix(".html")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(html_out)

    print(f"built {len(pages)} pages into {OUT}", file=sys.stderr)


if __name__ == "__main__":
    main()
