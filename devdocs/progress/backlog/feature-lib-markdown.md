---
track: B
prio: 45
type: feature
---

# A Markdown library — and the `markdown` Python shim over it

songformatter's help window does `import markdown` (python-markdown) and feeds
the HTML to `tkhtmlview`. That is the last import standing between
`SongFormatter.py` and a compile, and it is worth doing properly rather than
stubbing: a Markdown renderer is a generally useful library, and — if it is a
vendored C one — it doubles as a real cfront test case, the same way pdfgen does
for the PDF work.

## Two decisions, in order

### 1. Where the renderer comes from

| option | licence | shape | notes |
| --- | --- | --- | --- |
| **md4c** (mity/md4c) | MIT | `md4c.c` + `md4c-html.c` + headers, no build system needed | CommonMark-compliant, fast, C89-ish, no dependencies. The closest analogue to the pdgen choice. |
| **cmark** (commonmark/cmark) | BSD-2 | many files + CMake + generated tables | the reference implementation; correctness is beyond doubt, the build is not a single-file drop-in |
| **hoedown** | ISC | ~10 files | unmaintained; pre-CommonMark semantics |
| **our own, in Pascal** | ours | `lib/rtl/markdown.pas` | no third-party question at all; CommonMark is a big spec, and a half-implementation of a format everyone knows is worse than none |

Recommendation: **md4c, vendored, compiled by cfront** — it exercises the C
frontend on real third-party source (the flywheel), keeps the artifact
dependency-free and static, and its two-file shape is the one we already know
works (`import pdfgen` with a sibling `.c`). MIT is not public domain, so unlike
pdgen it carries an attribution obligation: the licence text ships with the
vendored source and is listed wherever we credit third-party code. That is a
smaller question than the general one, which is still open in
[[decide-3rd-party-vendor-vs-fetch]] — this ticket should not settle the general
policy, just follow it once it exists.

A Pascal implementation stays a legitimate fallback if vendoring is refused: the
subset a help window needs (headings, emphasis, code spans and fences, lists,
links, paragraphs) is a fraction of CommonMark, and it would then say so.

### 2. What the OUTPUT is consumed by

`markdown.markdown(text)` returns an HTML string, and songformatter hands it to
`tkhtmlview.HTMLLabel`. So the shim alone does not finish the job — something
must render that HTML into a Tk widget. Three ways, cheapest first:

- **plain-text degrade** — strip the markup and show the source text in a Text
  widget. Honest, tiny, and the help window stays usable.
- **markdown → Tk text TAGS directly** — skip HTML entirely: headings, bold,
  italic, code and bullets map onto `Text` tag configurations. This is the one
  that looks right and is still small, because the intermediate format is the
  thing that makes it big.
- **a real HTML renderer** — no. That is a project, not a follow-up.

Recommendation: shim `markdown.markdown()` for the API (a program may want the
HTML), and give the help window the **tag-based** renderer, filed separately as
`feature-lib-tkhtmlview` if it grows past a hundred lines.

## Acceptance

- `import markdown; markdown.markdown(src)` returns HTML for the CommonMark
  constructs the subset claims, diffed against python-markdown on a corpus of
  real `.md` files (this repo's own devdocs are a good one).
- The subset is stated in the unit header, and anything outside it fails loudly
  rather than silently dropping markup.
- `SongFormatter.py`'s help window opens under pxx.
- If md4c is vendored: it compiles under cfront unmodified, its licence ships
  with it, and a note records which upstream commit it came from.

## Why it is a good test case

A CommonMark parser is exactly the kind of C the frontend should be able to eat:
heavy pointer arithmetic, tables of function pointers, `#define` machinery, and
a large switch-driven state machine — with an oracle (python-markdown, or md4c
built by gcc) to diff against, which is the same shape as the zlib work.
