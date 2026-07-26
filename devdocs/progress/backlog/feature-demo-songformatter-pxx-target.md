---
summary: "songformatter as a pxx compile target (nilpy) — GUI editor + live preview"
type: feature
track: E
prio: 50
blocked-by: [feature-lib-pxxpdf-reportlab-compat, feature-nilpy-re-module, feature-nilpy-tkinter-facade]
---

# songformatter as a pxx compile target (GUI editor + live preview)

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

## Scope for v1 = the GUI app

The editor + live preview, NOT a CLI converter (the user corrected an earlier
headless framing: the GUI *is* the product — a musician opens a song and looks at
it). So the GUI pieces are v1 work, not follow-ups: a tkinter façade over `tk.pas`,
nilpy kwargs and callbacks, and the on-screen preview path.

The preview architecture question is now SETTLED, and settled on the app side
first: songformatter no longer previews through fitz/PyMuPDF at all. It draws the
preview with the SAME calls that produce the PDF, through an injected canvas
backend (`render_backend.TkCanvasBackend`, songformatter commit 29a874e) — the
"parallel canvas" option. No PDF readback, no MuPDF (AGPL, huge dep web), no PIL
requirement. pxxpdf therefore needs a second, screen-drawing backend rather than a
PDF renderer.

Screen-vs-PDF drift was the risk, and it is measured, not assumed: after three
fixes the canvas agrees with the PDF to within 1px in position and content extent
at both 1:1 and a fit-to-width zoom. The three fixes are the reusable lesson for
pxxpdf's screen backend:

1. Text is placed by its BASELINE in PDF space; toolkits anchor to the line box.
2. Font sizes must be given to the toolkit in PIXELS, not points — integer-only
   point sizes quantize twice and drew 13pt as 9pt (5.7% too large) at 0.655 zoom.
3. Place text word by word at the x its PDF metrics give it: toolkits advance
   glyphs by whole hinted pixels and the error reaches 10% across a line.

Verification method worth reusing: screenshot the canvas and render the same input
with `pdftoppm` at the matching resolution, then compare ink profiles for best-fit
offset and content extent.

## Steps (each domino gates the next)

1. [[bug-cfront-fegetround-unresolved-float-printf]] — pdfgen runs at all.
2. [[feature-nilpy-fallback-import]] — `try: import reportlab except: import pxxpdf`.
3. [[feature-lib-pxxpdf-reportlab-compat]] — the pxxpdf PDF backend under nilpy.
4. Compile the engine core under nilpy; catalog every remaining wall and file
   each into its owning lane (IR/codegen → A, dialect/frontend → N, RTL → B).
   **Step 4 has STARTED — see the wall catalog below.**
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
- **Tk GUI on pxx** (tkinter façade over `tk.pas` + nilpy kwargs/callbacks) — v1
  scope now, per the section above.
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

## Wall catalog (2026-07-26, measured against `stable_linux_amd64/default/pinned`)

Probed with 35 small `.py` cases covering what songformatter actually uses, rather
than fighting a 1833-line file one error at a time. Filed into their lanes:

**Blocks the very first module** (`key_analysis.py` fails on line 1):
- `import re` → nothing to bind to; pxx has no regex engine at all.
  [[feature-lib-regex-engine]] (B) + [[feature-nilpy-re-module]] (N).
  14 call sites surveyed: classes, alternation, non-greedy, non-capturing groups,
  `\d`/`\s`, one VERBOSE pattern.

**Silent wrong behavior — highest severity:**
- `"%.2f" % 3.14159` prints `0.0`, `"%d" % 42` prints `39`, `"%s" % "str"` prints
  `8568`. [[bug-nilpy-percent-string-format-garbage]] (N).
- Calling a lambda stored in a dict SEGFAULTS; from a list it yields an empty
  value. Evidence appended to [[feature-nilpy-lambda]] (N).

**Language gaps:**
- `return 1, 2` unparsed → [[feature-nilpy-tuple-return]]
- `def f(*args, **kw)` unparsed → [[feature-nilpy-star-args-kwargs]]
- `self.n = n` in a ctor demands an annotation →
  [[feature-nilpy-class-field-infer-from-ctor]]
- builtin errors aren't catchable (`int("nope")`, `1//0` abort past `except`) →
  [[feature-nilpy-catchable-runtime-errors]]
- `sum/max/min/any/all/sorted/set/map/filter/type` missing →
  [[feature-nilpy-aggregate-builtins]]
- f-string format specs (`{x:.2f}`, `{s:>5}`) →
  [[feature-nilpy-fstring-format-spec]]
- `g = lambda ...` doesn't parse; `sort(key=...)` errors → [[feature-nilpy-lambda]]
- `str.replace` / `.ljust` / `.zfill` and `from collections import Counter` →
  existing [[feature-nilpy-collections-and-string-methods]]
- `with open(...) as f` → existing [[feature-nilpy-file-io-and-comprehensions]]
- `for ... else` unparsed (minor, no ticket yet — songformatter doesn't use it)

**Already fine** (verified working, no ticket needed): slicing (`s[1:3]`,
`xs[1:3]`, negative, step), indexing, tuple unpack from literals and from
`.split()`, `dict.get/.items/.setdefault`, `in`, f-strings without specs,
comprehensions (list and dict), dataclasses with `field(default_factory=list)`,
classes with annotated fields, `global`/`nonlocal`, kwargs at the CALL site,
`raise`/`except X as e` for Python-raised exceptions, `"-" * 5`, `[0] * 3`,
`enumerate`, `zip`, `range`, `len`, `str`, `int`.

Also note: a `.py` extension compiles as nilpy exactly like `.npy` (no rename
needed), and the compiler must be invoked from the repo root for RTL unit
resolution.

**Not a Track A gap after all:** the libc-free `exec` this app needs for its
Preview PDF action already exists (`ExecutePipeline`, `lib/rtl/sysutils.pas`,
ticket `feature-sys-process-spawning` done). Only the nilpy binding is missing →
[[feature-nilpy-process-exec-binding]], and the app can carry a stub until then.

## Log
- 2026-07-25 — filed as the umbrella goal from the planning session.
- 2026-07-26 — rescoped headless → GUI-MVP; preview architecture settled as the
  parallel canvas and shipped on the app side (songformatter 29a874e, 0d7a5c2);
  step-4 wall catalog added and 9 tickets filed.

## Wall catalog, second pass (2026-07-26 — after regex + re + BOM landed)

Where each module now stops, with the pinned stable plus the three commits below
(`1e29abdf` regex engine, `ca4dac8d` the `re` module, `14e5f5e9` the BOM fix):

| module | first wall now |
| --- | --- |
| `key_analysis.py` | `from collections import Counter` — [[feature-nilpy-collections-and-string-methods]] |
| `settings.py` | `import configparser` — [[feature-nilpy-configparser]] |
| `convertrawtext.py` | `import tkinter` — [[feature-nilpy-tkinter-facade]] |
| `SongFormatter.py` | `import json` binds the Pascal RTL unit — [[bug-nilpy-stdlib-name-binds-pascal-unit]] |

`import re` is GONE as a wall: `key_analysis.py` used to die on line 1 and now
reaches line 4. `convertrawtext.py` used to die on line 1 with "unexpected
character" (its UTF-8 BOM) and now reaches line 2.

The `import json` finding is the one with design weight, and it cuts both ways:
NilPy resolves `import X` through the Pascal unit resolver, which is precisely how
`re` was provided with zero frontend change — but it means ANY Python stdlib name
colliding with an RTL unit name binds to Pascal code (`json`, `math`, `net`,
`http`, `random`, `collections`…). Needs a policy: allow-list the deliberate shims,
or give Python shims their own search path. See that ticket.

## Wall catalog, third pass (2026-07-26 — after Counter + the dict factory)

`key_analysis.py` has now moved through three walls in a row, each fix revealing
the next — which is the flywheel working as intended:

`import re` (line 1) → `from collections import Counter` (line 4) →
`field(default_factory=dict)` → **tuple type annotations** (`Nil Python: tuple
types are not supported yet`).

So the current wall per module:

| module | first wall now |
| --- | --- |
| `key_analysis.py` | tuple types — see [[feature-nilpy-tuple-return]], which needs widening to cover tuple TYPES and annotations, not just `return 1, 2` |
| `settings.py` | `import configparser` — [[feature-nilpy-configparser]] |
| `convertrawtext.py` | `import tkinter` — [[feature-nilpy-tkinter-facade]] |
| `SongFormatter.py` | `import json` binds the Pascal RTL unit — [[bug-nilpy-stdlib-name-binds-pascal-unit]] |

Tuples are now the critical path for the engine modules, and they show up three
ways: as annotations (`tuple[str, float]`), as returns (`return "xxxxxx", [0]*6`),
and as `re.findall` results with 2+ groups (where the `re` module returns lists
today — see that unit's header). One feature, three consumers.

Two findings filed from this pass, both beyond songformatter:
- [[bug-pascal-subclass-inherited-members]] — subclassing is half-wired FOUR ways
  (inherited fields and methods invisible unqualified, wrong `Create`, inherited
  default property loses subscript assignment). It forced Counter to ship as a
  dict mode instead of a subclass, and it blocks the natural shape for
  configparser's `optionxform` override.
- [[feature-nilpy-augmented-subscript-assign]] — `d[k] += 1` and `xs[i] += 5` are
  "not an lvalue". Pre-existing, reproduced on the pinned stable, and the most
  common counting idiom in Python.

**Diagnostic line numbers are unreliable and it is costing real time.** Three
separate errors this session pointed at the wrong line: `import json` reports line
64 in a 1-line file, the dataclass-factory error reported line 6 (a list literal)
for a field on line 53, and the augmented-assignment error reports one line past
the statement. Each sent me reading the wrong code first. Worth a ticket of its
own if it keeps happening.
