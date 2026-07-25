---
summary: "pxxpdf — pxx pdfgen-backed, reportlab-compatible PDF library (nilpy)"
type: feature
track: B
prio: 50
blocked-by: [bug-cfront-fegetround-unresolved-float-printf, feature-nilpy-fallback-import]
---

# pxxpdf — pxx pdfgen-backed, reportlab-compatible PDF library

- **Type:** feature (library / PDF) — **Track B** (file-owned), first consumer is
  Track E [[feature-demo-songformatter-pxx-target]].
- **Status:** backlog
- **Opened:** 2026-07-25 — songformatter planning session. Replaces
  `feature-reportlab-mimic-over-pdfgen`. Full design in
  [[frank2-songformatter-pxx-target]].

## What it is (name: `pxxpdf`)

A **pxx library** (reusable tooling, NOT songformatter-owned) that presents
**reportlab's canvas API** but is honestly named `pxxpdf` and backed by
**pdfgen** (AndreRenaud/pdfgen, C, public-domain). Module docstring carries the
full description: "pxx pdfgen-backed, reportlab-compatible PDF wrapper." Any
reportlab-using Python then compiles under nilpy via a fallback import
([[feature-nilpy-fallback-import]]):

```python
try:    from reportlab.pdfgen import canvas   # cpython
except ImportError: from pxxpdf import canvas  # nilpy
```

It mimics reportlab's **API** (so downstream `canvas.Canvas(...)` calls are
identical on both paths) — NOT reportlab's **name** (no impersonation) and it is
NOT app-specific.

## Backend = VENDORED pdfgen (policy note)

pdfgen is a **dependency** (the product needs it), not a throwaway corpus — so
Rene's call is to **vendor it in-tree** (e.g. `lib/pxxpdf/vendor/pdfgen.c` +
`.h`), giving self-contained builds + the ability to patch it for pxx (the
`M_SQRT2`/fenv fixes). Safe because pdfgen is **public-domain (Unlicense)** —
redistribution is legally clean, single-file, tiny. NOTE: this is the FIRST
committed third-party source in the repo (today `external/` and
`library_candidates/` are BOTH gitignored — zero foreign source committed). The
general policy is escalated to [[decide-3rd-party-vendor-vs-fetch]]; pxxpdf is not
blocked on it (PD = vendor-safe now).

Static-linked via `import pdfgen` (sibling `pdfgen.c`, cfront compiles it into the
ELF — proven, `test/test_c_import.pas`) → single libc-free binary, zero runtime
deps.

## API surface (the reportlab subset songformatter imports; convertrawtext.py:7-29)

`canvas.Canvas` is the work (facade holds color/font/linewidth state, flushes per
pdfgen call):

| reportlab | pdfgen |
|---|---|
| `Canvas(f, pagesize=A4)` | `pdf_create` + first `pdf_append_page` |
| `setFont/setFillColorRGB/setStrokeColorRGB/setLineWidth` | facade state (×255 color) |
| `drawString(x,y,t)` | `pdf_add_text(pdf,NULL,t,size,x,y,PDF_RGB(...))` |
| `beginText/textLine/drawText` | accumulate → per-line `pdf_add_text` |
| `line/rect/circle` | `pdf_add_line` / `pdf_add_[filled_]rectangle` / `pdf_add_circle` |
| `showPage` / `save` | `pdf_append_page` / `pdf_save`+`pdf_destroy` |
| `drawImage` | `pdf_add_image_*` — **deferred to v1.x** |

Plus trivial submodules the imports need: `pagesizes` (A4=595×842pt), `units`
(mm,cm), `colors` (white/black/red…), `graphics.shapes` (Circle/Rect/Line),
`pdfbase.pdfmetrics` (only `getRegisteredFontNames`), `lib.utils.ImageReader`
(stub until images). Coordinates match (both PDF-native bottom-left points).
pdfgen covers the whole canvas layer (has `pdf_get_font_text_width`=stringWidth,
wrap, rotate). NOT covered: `reportlab.platypus` (doc-layout) — out of scope,
songformatter doesn't use it.

## Dev aid (optional)

No pip binding to C pdfgen exists (PyPI `pdfgen` = unrelated Pyppeteer tool). For
fast iteration, ctypes-wrap `gcc pdfgen.c→.so` so the SAME pxxpdf runs under
cpython and is verifiable against a gcc-built-pdfgen oracle before nilpy compile.

## Acceptance

- `from pxxpdf import canvas` under nilpy produces a valid `%PDF` matching the
  reportlab output for a sample `example_songs/*.txt`.
- Needs [[feature-nilpy-fallback-import]] (import path) +
  [[bug-cfront-fegetround-unresolved-float-printf]] (pdfgen runs).
- Image path (drawImage/PIL) deferred, tracked as follow-up.

## Log
- 2026-07-25 — filed, replacing feature-reportlab-mimic-over-pdfgen; name `pxxpdf`,
  pdfgen vendored.
