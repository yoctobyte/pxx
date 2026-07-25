---
summary: "songformatter as a pxx compile target (nilpy) — headless CLI PDF converter"
type: feature
track: E
prio: 50
blocked-by: [feature-lib-pxxpdf-reportlab-compat]
---

# songformatter as a pxx compile target (headless CLI converter)

- **Type:** feature (example app built WITH pxx) — **Track E** (file-owned by B;
  build with `$(PXX_STABLE)`, never rebuild the compiler).
- **Status:** backlog
- **Opened:** 2026-07-25 — planning session with the user. Full design in memory
  [[frank2-songformatter-pxx-target]].

## Goal

Compile Rene's real Python app **songformatter** (`~/songformatter`, gh
`yoctobyte/songformatter`) with nilpy → standalone binary. Two aims: (1) improve
the music tool; (2) a real-world nilpy test case that feeds the flywheel
([[frank2-mission-compile-real-world-asis]]). **No rewrite to Pascal**; app source
stays cpython-compatible (principal goal). Only change to songformatter = a
fallback import (`try: from reportlab… except ImportError: from pxxpdf…`); pxxpdf
is a reusable pxx lib presenting reportlab's API over pdfgen (honest name, not
impersonating reportlab, not app-owned).

## Scope for v1 = headless CLI converter

`songformatter in.txt out.pdf` — the `convertrawtext.py` engine (parse → layout →
PDF), NOT the Tk GUI. Rationale: the full Tk GUI is far (songformatter uses the
Python tkinter OBJECT API; nilpy has only `import tk` flat-function + poll events,
no kwargs/callbacks; Windows needs PE backend + win32 widgetset — all backlog).
GUI + Windows one-click = later tickets.

## Steps (each domino gates the next)

1. [[bug-cfront-fegetround-unresolved-float-printf]] — pdfgen runs at all.
2. [[feature-nilpy-fallback-import]] — `try: import reportlab except: import pxxpdf`.
3. [[feature-lib-pxxpdf-reportlab-compat]] — the pxxpdf PDF backend under nilpy.
4. Compile the engine core under nilpy; catalog every remaining wall and file
   each into its owning lane (IR/codegen → A, dialect/frontend → N, RTL → B).
   Expect nilpy-subset hits: 1-based string slicing, O(N) dicts, missing stdlib.
5. Diff output vs the cpython/reportlab reference on `example_songs/` (37 songs).

Build glue (Makefile / `-Fu` invocation + pdfgen fetch) = academic; can live as a
docs note, not full automation.

## Acceptance

- The headless converter, compiled by nilpy, turns a sample `example_songs/*.txt`
  into a valid PDF whose layout matches the reportlab reference.
- Binary is self-contained (static pdfgen, libc-free crtl; `ldd` = minimal/none).
- Walls found during step 4 are filed as tickets in their owning lanes.

## Follow-ups (separate tickets when reached)

- **Image path** — pdfgen embeds PNG/JPEG/BMP natively (`pdf_add_image_file`), so
  NO PIL needed for embedding. PIL is only used for effects (opacity/blur/enhance
  on the bg image); those drop under nilpy. PIL itself = CPython C-extension, not
  nilpy-compilable. Wrap `from PIL import …` in the same `try/except ImportError`.
- **Tk GUI on pxx** (tkinter façade over `tk.pas` + nilpy kwargs/callbacks).
- **GUI preview architecture (the fitz question)** — today songformatter previews
  via render→PDF then PDF→pixmap (fitz/PyMuPDF, a MuPDF C lib+binding; GUI-only,
  not nilpy-compilable). Double work but pixel-perfect (preview = real PDF). Two
  futures on pxx: (a) a PDF *renderer* (MuPDF-class — big) to keep render-back;
  (b) give `pxxpdf`'s canvas a SECOND backend drawing to GTK/screen — same drawing
  code, two outputs, no PDF-readback, no fitz (risk: screen-vs-PDF render drift,
  not guaranteed identical). The pxxpdf canvas abstraction is what makes (b)
  possible. Future decision, not v1.
- **Windows one-click binary** (PE backend + win32 widgetset + tk-windows-compat).
- **Tool improvement:** exact chord x-positioning via pdfgen `pdf_get_font_text_width`.

## Log
- 2026-07-25 — filed as the umbrella goal from the planning session.
