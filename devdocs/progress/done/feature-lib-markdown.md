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

## 2026-07-31 — the fallback renderer is DONE and now VERIFIED against two oracles

The Pascal fallback this ticket names was already written
(`lib/rtl/markdown.pas`, plus `lib/pcl/tkhtmlview.pas` and `lib/rtl/html.pas`).
What was missing is the half that makes it trustworthy: the differential this
ticket's acceptance asks for. It has now been run, and it found two real bugs.

### The differential

An 18-document corpus covering exactly the claimed subset — ATX headings,
paragraphs with soft line breaks, fenced and indented code, unordered and
ordered lists, blockquotes, horizontal rules in all three spellings, and the
inline forms — rendered by `markdown.pas` and diffed against **two** oracles:
python-markdown 3.10.3 (with `fenced_code`, since base python-markdown has no
fences) and markdown-it-py in `commonmark` mode. Whitespace between tags is
normalised; nothing else is.

**Result: 18/18 identical to the CommonMark reference. 17/18 identical to
python-markdown** — the one exception is `doc1.md`, where python-markdown merges
an ordered list that immediately follows an unordered one into the same `<ul>`;
CommonMark keeps them separate, and so do we. Checked against markdown-it rather
than argued from the spec.

`markdown.markdown(...)` — the Python entry point — was checked separately from
a `.npy` and is byte-identical to python-markdown on the plain call and on both
extensions the shim claims (`nl2br`, `toc`).

### Two bugs the oracle found, both fixed here

1. **A blockquote collapsed its soft line breaks.** `> one` / `> two` joined
   with a SPACE, where a paragraph in the same renderer already preserved the
   newline. Both oracles keep it. Now it does too, and honours `nl2br` the way
   the paragraph path does.
2. **Emphasis had no flanking rule, so ordinary prose was mangled.**
   `2 * 3 * 4` came back as `2 <em> 3 </em> 4`, and `a_b_c` as
   `a<em>b</em>c`. CommonMark's rule is that a delimiter opens only when what
   follows is not whitespace and closes only when what precedes is not, and that
   `_` never works inside a word. Implemented for `*`, `_` and `**` — `2 ** 3`
   is arithmetic again.

The second one is the kind this repo cares about most: silent, and it corrupted
text that contains no markup at all.

### Regression

`test/lib_markdown.pas` — the corpus and its expectations, GENERATED from
markdown-it's output rather than from reading our own back — wired into
`lib-test`. 17 cases plus a summary line.

### What is still open, and where it lives

- **md4c.** Vendoring a real CommonMark implementation and compiling it with
  cfront is the better long-term answer this ticket recommends, and it is still
  governed by [[decide-3rd-party-vendor-vs-fetch]]. Not settled here, by design.
  The bar it now has to clear is higher than when this ticket was written: the
  fallback matches the CommonMark reference on everything it claims.
- **"SongFormatter.py's help window opens under pxx"** is not blocked on
  markdown. That module compiles; the app stops earlier, in
  `FormatText.set_document_text` — see
  [[feature-demo-songformatter-pxx-target]]. That acceptance line rides with
  the demo ticket.

## Log
- 2026-07-31 — resolved, commit 64fd3be14.
