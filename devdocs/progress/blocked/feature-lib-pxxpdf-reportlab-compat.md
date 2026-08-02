---
summary: "pxxpdf — pxx pdfgen-backed, reportlab-compatible PDF library (nilpy)"
type: feature
track: B
prio: 50
blocked-by: [decide-pxxpdf-ticket-obsolete]
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

## STALE as filed — re-measured 2026-08-02

Re-read against the tree rather than the ticket text. Most of what this ticket
asks for already exists, under a different design than it describes, and its
acceptance criterion already passes.

**Vendoring: done.** `lib/vendor/pdfgen/` (pdfgen.c, pdfgen.h, LICENSE,
README.md) has been committed since 2026-07-28. The ticket's "this is the FIRST
committed third-party source in the repo" framing and the accompanying policy
caution are historical — that step was taken.

**The design changed: PCL mimic units, not a `pxxpdf` Python module.** The
ticket specifies a nilpy module named `pxxpdf` reached through a
`try: from reportlab... / except ImportError: from pxxpdf...` fallback. What was
actually built is a set of Pascal PCL units resolved by the compiler's own
import mapping (`compiler/pyparser.inc:16175` — dots become underscores, then
`mimic_` prefix):

```
lib/pcl/mimic_reportlab_pdfgen.pas            lib/pcl/mimic_reportlab_lib_colors.pas
lib/pcl/mimic_reportlab_pdfbase.pas           lib/pcl/mimic_reportlab_lib_pagesizes.pas
lib/pcl/mimic_reportlab_pdfbase_pdfmetrics.pas  lib/pcl/mimic_reportlab_lib_units.pas
                                              lib/pcl/mimic_reportlab_lib_utils.pas
```

So application code writes plain `from reportlab.pdfgen import canvas` and the
compiler redirects it, printing `note: reportlab_pdfgen -> mimic_reportlab_pdfgen
(shim, subset)`. No `pxxpdf` name, no fallback-import idiom needed. This is a
better shape than the ticket's (unmodified upstream source compiles as-is), but
it means the ticket's name, module layout and import strategy are all obsolete.

**The API table is implemented**, including `drawImage`, which this ticket
explicitly deferred to v1.x: `setFont`, `setFillColorRGB`, `setStrokeColorRGB`,
`setFillColor`, `setStrokeColor`, `setLineWidth`, `drawString`, `line`, `rect`,
`circle`, `beginText`/`textLine`/`textOut`/`drawText`, `stringWidth`,
`showPage`, `save`, `setBlendMode`, `setTitle`, `setAuthor`, plus
`PDFTextObject.setTextOrigin`/`moveCursor`/`getX`/`getY`
([[feature-lib-reportlab-shim-pdftextobject]], done).

**Acceptance already passes.** A nilpy program using `canvas.Canvas`, `A4`,
`mm`, `setFont`, `setFillColorRGB`, `drawString`, `line`, `rect`, `beginText`/
`textLine`/`drawText`, `showPage`, `save` compiles and runs, producing a 3045-byte
`%PDF-1.3` with a correct `%%EOF` whose text `pdftotext` extracts correctly.

**One real bug found while measuring this**, and fixed rather than left in the
ticket: `M_SQRT2` was undefined in crtl's `math.h` and therefore silently zero,
so pdfgen's circle Bezier offset was `-1.333*r` instead of `+0.552*r` and every
circle it drew was garbage. Filed and resolved as
[[bug-b-crtl-math-constants-missing-silently-zero]].

### What is actually left

Not "build pxxpdf" — the remaining work is narrower and should be re-filed as
such rather than carried under this ticket's obsolete framing:

1. **Fidelity against the reportlab oracle.** Acceptance says "matching the
   reportlab output for a sample `example_songs/*.txt`". Only *validity* has
   been demonstrated, not agreement with real reportlab. That is the honest
   open item and wants a differential test against CPython+reportlab.
2. **`strings.h` resolves from the host system**, not pxx's headers — the
   compiler warns that ABI/macro mismatches "may silently misbehave" while
   building pdfgen. Left open, see the follow-up ticket.
3. **`time` and `bcmp` bind to Pascal routines with the wrong parameter count**
   while building pdfgen ("the argument list will not arrive as written"), which
   is a silent-wrong-behavior warning. Also left open as a follow-up.

Recommendation: close this ticket in favour of a scoped
`feature-lib-reportlab-fidelity-vs-oracle`, since every structural item it lists
is done and its name/design no longer match the tree. Flagged for **Track U**
rather than decided here — closing a prio-50 feature ticket is the user's call,
not mine.
