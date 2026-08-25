---
summary: "songformatter as a pxx compile target (nilpy) — GUI editor + live preview"
type: feature
track: E
prio: 68
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

## Wall catalog, fourth pass (2026-07-26 — unions, tuples, keyword-only marker)

`key_analysis.py` (762 lines) has walked SIX walls this session and now reaches
line 29, having passed every def, dataclass, annotation and tuple return in the
file:

`import re` → `from collections import Counter` → `field(default_factory=dict)` →
`tuple[...]` annotation → `int | None` annotation → `return a, b` → bare `*`
keyword-only marker → **`dict.fromkeys`** (line 29).

`dict.fromkeys(MODAL_KEYS)` is a classmethod on dict, so it needs the pylib method
plus whatever the dotted-call path needs to resolve `dict.` as a TYPE rather than a
value. Small, and it is the only thing left between this module and a compile —
worth doing next simply to get the first songformatter module through.

Landed for these: tuple annotations and returns both lower to TPyList; PEP 604
unions get Optional's exact treatment (including the widening that keeps a real 0
distinct from None); the keyword-only marker is consumed and dropped.

Filed on the way, both pre-existing:
- [[feature-nilpy-optional-string-param-accepts-none]] — passing None to an
  `Optional[str]` PARAMETER does not match the overload (reproduces on the pinned
  stable with the Optional spelling, so unions inherit it, not introduce it).
- [[feature-nilpy-augmented-subscript-assign]] and
  [[bug-pascal-subclass-inherited-members]] from the previous pass.

## Wall catalog, fifth pass (2026-07-26 — dict.fromkeys)

`key_analysis.py`: SEVEN walls cleared, now past every module-level statement and
into the function bodies. Current wall:
`.to_text() on a dynamically-typed value is ambiguous` — the receiver's class
cannot be pinned statically, which is the existing
[[feature-nilpy-runtime-method-dispatch-on-variant]]. That is the last known gap
for this module, and it is a real feature rather than a shim.

`settings.py`: surveyed, and the blocker is NOT the INI parsing (a dull surface) —
it is `class CasePreservingConfigParser(configparser.ConfigParser)`, which needs a
dotted base class AND working subclass overrides. So
[[feature-nilpy-configparser]] is blocked in practice by
[[bug-pascal-subclass-inherited-members]]. That bug is now on the critical path for
two modules, which raises its value above its prio-60 filing.

Recommended order from here:
1. [[bug-pascal-subclass-inherited-members]] — unblocks configparser, and pylib
   types can stop working around it (Counter is a mode flag because of it).
2. [[feature-nilpy-runtime-method-dispatch-on-variant]] — finishes key_analysis.py.
3. [[feature-nilpy-configparser]] — then settings.py.
4. [[feature-nilpy-tkinter-facade]] — convertrawtext.py and the GUI (the big one).
5. [[bug-nilpy-stdlib-name-binds-pascal-unit]] — SongFormatter.py's `import json`.

## Wall catalog, sixth pass (2026-07-27 — `*args` / `**kwargs` rungs 1+2)

[[feature-nilpy-star-args-kwargs]] rungs 1 (collection) and 2 (`print(*args)`) are
in. Both modules that were stuck on it moved:

| module | first wall now |
| --- | --- |
| `convertrawtext.py` | `import tempfile` (line 64) — the module, not the syntax |
| `settings.py` | `import tkinter as tk` (line 2) — import ALIASING is unsupported |
| `key_analysis.py` | runtime method dispatch on a variant (unchanged) |
| `SongFormatter.py` | `import json` binds the Pascal RTL unit (unchanged) |

Two things worth recording from the pass:

- **settings.py's wall jumped BACKWARDS in line order, which is progress, not a
  regression.** It used to die at line 102 because the def-shell PRE-PASS parses
  every `def` header before the module body runs; with `getF(*args, **kwargs)`
  parsing, the body is finally reached and dies on line 2 instead. A pre-pass
  failure always outranks a body failure regardless of line number — worth
  remembering when reading these tables.
- **`import X as Y` is a new, separate wall** and a small one (nilpy maps `import
  X` onto the Pascal unit resolver, which already has `uses ... as` —
  [[feature-uses-alias-as]], done). It stands in front of the tkinter façade for
  settings.py, so it is the cheapest next step on this module.

Rung 3 (forwarding `*args`/`**kwargs` into a fixed-arity callee) is still open and
is what settings.py's `getF` ultimately needs; it did not block the compile any
further because the wall above it moved first.

## Wall catalog, seventh pass (2026-07-27 — a long run of frontend work)

Landed this session, each one a wall a module was standing on: `*args`/`**kwargs`
(all three rungs — collection, `print(*args)`, and forwarding into a fixed-arity
callee), `import X as Y`, unit-qualified class construction (`tk.Frame(...)`),
one Exception class serving both the Python and the sysutils surface, runtime
method dispatch across unrelated classes, Python `or`/`and` returning an OPERAND,
empty-string falsiness, raw strings, `set(iterable)`, class attributes,
`del <local>`, dict for-in over a variant, and an unannotated `__init__`.

| module | first wall now |
| --- | --- |
| `key_analysis.py` | nested comprehension — [[feature-nilpy-nested-comprehension]] |
| `settings.py` | the tkinter façade's surface (`grid_rowconfigure`, …) — [[feature-nilpy-tkinter-facade]] |
| `convertrawtext.py` | `import tempfile` — no shim yet |
| `SongFormatter.py` | `from pathlib import Path` — no shim yet |

`settings.py` also has a RUNTIME blocker even once it compiles:
[[bug-nilpy-omitted-variant-default-segfaults]] — reading a variant parameter
that carries a default crashes. That ticket has the measured matrix.

**What the remaining work looks like, honestly.** The frontend gaps are nearly
worked out; what is left is mostly LIBRARY surface, and it is not small:

1. **The tkinter façade is ~9 classes and 72 members**; songformatter needs Menu,
   Notebook/ttk, Text, Toplevel, PanedWindow, filedialog, messagebox, the event
   system (`bind`, `event_generate`), and the rest of the geometry managers. This
   is Track B work and is the single biggest item left.
2. **`tempfile` and `pathlib`** — two small T1 shims (NamedTemporaryFile with
   `.name`/`.close()`; Path with `/`, `.stem`, `.name`, `.is_file`, `.open`).
3. **`markdown` and `tkhtmlview`** for SongFormatter's help window — third-party,
   and the honest answer there is probably to make that window optional rather
   than shim a Markdown renderer.
4. **The nested comprehension** and the defaulted-variant-parameter crash, both
   filed with the analysis needed to start.

## Naming strategy reversed (2026-07-26, Rene)

The "honest name, not the reportlab name" decision is REVERSED. It put a change in
the APPLICATION (a fallback import) to work around a naming scruple in the
COMPILER's library set, which is backwards for a project whose mission is compiling
existing source as-is. A shim is now NAMED for the module it implements, so the app
needs no change at all.

Legitimacy (may we implement a named library at all, what clean room requires, what
we must never claim): `devdocs/legal/interface-compatibility.md`.
Technical policy: `devdocs/dev/python-compat-tiers.md` — three tiers (T1 name-shim,
T2 vendored C core with a Python face, T3 compile the actual package), the rule
that T1 defers to a filed T3 ticket and must fail loudly outside its subset, and
what we may and may not write (interface names and clean-room implementations yes;
their code, their docs, and claiming pxx "runs reportlab" no).

Consequences for this ticket:
- [[feature-lib-pxxpdf-reportlab-compat]] becomes a `reportlab`-named shim over the
  same vendored pdfgen backend, once [[feature-nilpy-dotted-package-imports]] lands
  (`from reportlab.pdfgen import canvas` needs the dotted form).
- songformatter's fallback import (`12cf40e`, already pushed) comes OUT at that
  point and the app is unmodified source again. It is the last app-side change.

## Pass six — key_analysis.py RUNS (2026-07-27)

The first songformatter module is DONE end to end: `key_analysis.py` compiles
and its output matches CPython's for the same chord list (`C / weighted / 8`).
[[bug-nilpy-key-analysis-compiles-but-segfaults]] is resolved; three tickets came
out of the hunt, and one of them was not a NilPy bug at all:

| what | lane |
| --- | --- |
| [[bug-nativeuint-cast-widens-load]] — `NativeUInt(field)` loaded eight bytes from a four-byte field | **A** (pure Pascal, target-independent, silent corruption) |
| [[bug-nilpy-callable-return-abi-mismatch]] — a def passed to `Callable[...]` was marshalled by the ANNOTATION | N |
| [[bug-nilpy-dict-views-and-result-alias]] — `d.values()`/`d.keys()` jumped to 0; a local named `result` aliased the function result; `len(<variant>)` did not compile; float f-string specs halted | N |

The demanding-consumer pattern held again: one real 762-line module surfaced a
core codegen bug that no test in the suite had touched.

### Where the other five modules stand

## 2026-07-28: convertrawtext.py COMPILES

The file the track is named for parses, resolves and links end to end — 1960
lines, 2141 procs, a 3.7 MB binary. What it took, beyond the walls listed above:

- an `import` inside a def emitted the imported unit's code into the gap between
  the def's recorded body address and its prologue, so calling the def entered
  that UNIT's first routine (`try: import math` in a function returned math's pi)
- `*args` / `**kwargs` on a METHOD — the header was rejected and the
  arity-driven call loops could not call one
- a nested `class` in a class body (reportlab's blendmode namespace)
- `self.x, self.y = x, y` — an attribute as an unpacking target
- `for (x, y, z) in xs:` — a parenthesised target list
- a call omitting every optional argument (`filedialog.askopenfilename()`)
- tkinter's `messagebox` / `filedialog` / `w.config` / `Scrollbar.config`,
  Canvas scroll options, `create_oval` / `create_image`, and REAL canvas
  coordinates

Compiling is not running. The next wall is
[[bug-nilpy-param-with-string-default-reads-garbage]]: a def's declared default
is never the value the callee sees, and songformatter writes defaults
everywhere. [[bug-nilpy-class-attr-instance-traversal-crashes]] is on the same
path (reportlab's blendmode is read through it).

`render_backend.py` compiles as an IMPORT but not standalone — as a program of
its own it ends in "invalid symbol in lea", which is a module-with-no-main
artefact worth its own look.

## 2026-07-28: SongFormatter.py COMPILES — the whole application

3,973 lines of Python across five modules (SongFormatter, convertrawtext,
render_backend, settings, key_analysis) into a 4.3 MB static binary, 2,270
procs. No compiler wall left in its path.

The run from "convertrawtext parses" to here:

- [[bug-nilpy-module-ast-recycled-by-nested-unit-compile]] — the AST arena is
  per-proc scratch and a module holds nodes across the whole file, so importing
  a module that imports another recycled the outer one's statement list. The
  floor has to track the list as it GROWS, not just its start.
- [[bug-nilpy-ambiguous-dynamic-field-needs-runtime-dispatch]] — `event.x`,
  resolved by dispatching on the receiver's real class at run time.
- keyword arguments binding to the CONSTRUCTOR's parameters before the class's
  fields; a qualified exception class inside a tuple; `tk.X` falling back to the
  `NAME_` spelling; any unmodelled `sys.<attr>` raising rather than reading as
  zero; module globals a def reads from further up the file.
- libraries: `lib/rtl/markdown.pas`, `lib/pcl/tkhtmlview.pas`, the Python `json`
  surface on `lib/rtl/json.pas`, `pathlib.Path.open`, tkinter's `Toplevel`,
  menus (`config(menu=)`, `add_cascade`, `postcommand`, accelerators), canvas
  scroll options and real (non-integer) coordinates, `messagebox`, `filedialog`.

**Compiling is not running.** The session file does not round-trip yet:
[[bug-heap-dict-literal-then-two-parses-corrupts]] — the ALLOCATOR, not json (a
dict literal plus two parses in one program; clean under `-dPXX_LIBC_HEAP`,
the same discriminator as [[bug-c-unit-crashes-when-sysutils-is-used]]). Next
after that: an end-to-end GUI run under Xvfb, and a PDF diff against the
reportlab reference.

| module | wall |
| --- | --- |
| `key_analysis.py` | **none — compiles and runs** |
| `kadrv.py` | `import key_analysis` — [[feature-nilpy-py-module-loader]] (T3) |
| `convertrawtext.py` | its imports all RESOLVE now (the module loader, plus ast/atexit/subprocess/io shims); the walls left are [[bug-nilpy-module-class-vmtaddr]] (key_analysis as a module) and [[bug-unit-const-shadows-a-field]] (re.pas's `S = 4` captures pathlib's `s` field, pre-existing, plain Pascal too) |
| `settings.py` | tkinter façade: `create_window((0,0), window=..., anchor=...)` — [[feature-nilpy-tkinter-facade-widening]] |
| `render_backend.py` | `from reportlab...` — [[feature-lib-pxxpdf-reportlab-compat]] + dotted imports |
| `SongFormatter.py` | `import markdown` (help window) — [[feature-lib-markdown]]: vendor md4c under cfront, shim `markdown.markdown()`, and render into Tk TAGS rather than HTML |

Next rung: the tkinter façade (settings.py is otherwise clean), then the `.py`
module loader — which is what turns six separate files into one program.


## Pass seven — settings.py RUNS (2026-07-28)

The second songformatter module is done end to end: **settings.py builds its
whole editor — 60 child widgets, exactly CPython's count — under Xvfb, from
unmodified app source.** Five bugs stood between compiling and running, and the
first three are silent-corruption class:

| what | lane |
| --- | --- |
| [[bug-nilpy-pydict-v-borrowed-reference]] — a dict out of a dict was unboxed as a BORROWED reference; the caller's release freed a live object and corrupted the free list | N |
| [[bug-nilpy-comparison-return-type-from-operands]] — an unannotated def returning a comparison typed its result from the operands (and tuple membership compared by identity) | N |
| [[bug-nilpy-bound-method-coerced-to-string]] — a bound method passed to a string option compiled, and Tk then evaluated garbage: the event loop HUNG four layers from the cause | N |
| StringVar had no `trace_add`; a canvas item spec refused a tag (`bbox("all")`); a multi-word option value was not braced, so `-scrollregion 0 0 500 1026` reached Tk as `0` plus three stray arguments | B |
| [[feature-nilpy-lambda-compiled-closure]] slice one — a call-shaped lambda is now COMPILED, which is what makes `configure(scrollregion=...)` bind by NAME (pyeval appended keyword args positionally: [[bug-nilpy-pyeval-host-kwargs-positional]]) | N |

Scroll wiring now follows CPython's tkinter: `Scrollbar(command=canvas.yview)`
and `configure(yscrollcommand=scrollbar.set)` wire Tcl straight to the other
widget's subcommand rather than calling back into Python. The general case (a
plain callable that must receive Tk's own arguments) is filed as
[[feature-lib-tkinter-callable-options-with-args]] and fails loudly meanwhile.

Where the modules stand now:

| module | wall |
| --- | --- |
| `key_analysis.py` | **none — compiles and runs** |
| `settings.py` | **none — compiles, runs, builds all 60 widgets** |
| `kadrv.py` | `import key_analysis` — [[feature-nilpy-py-module-loader]] (T3) |
| `convertrawtext.py` | its imports all RESOLVE now (the module loader, plus ast/atexit/subprocess/io shims); the walls left are [[bug-nilpy-module-class-vmtaddr]] (key_analysis as a module) and [[bug-unit-const-shadows-a-field]] (re.pas's `S = 4` captures pathlib's `s` field, pre-existing, plain Pascal too) |
| `render_backend.py` | `from reportlab...` — [[feature-lib-pxxpdf-reportlab-compat]] + dotted imports |
| `SongFormatter.py` | `import markdown` (help window) — [[feature-lib-markdown]]: vendor md4c under cfront, shim `markdown.markdown()`, and render into Tk TAGS rather than HTML |

Also filed on the way: [[feature-nilpy-function-values]] (`f = add`,
`g = lambda ...` at statement level, calling a function value out of a
container), [[bug-nilpy-pyeval-prints-bool-as-number]],
[[bug-nilpy-qualified-proc-omitted-default]].

Technique that settled the hardest one: `-dPXX_LIBC_HEAP` puts the pxx heap on
libc malloc so valgrind sees every allocation. A native-allocator crash that
makes no sense at the crash site is a use-after-free until proven otherwise.


## Pass eight — the PDF backend is real; the class namespace is the blocker (2026-07-28)

The reportlab side went from "nothing exists" to "a working backend that a
Pascal program drives", and then stopped on a language-level question rather
than on anything reportlab-shaped.

**Landed.** AndreRenaud/pdfgen is vendored (`lib/vendor/pdfgen`, Unlicense, the
first third-party source committed here) and compiles under cfront as a UNIT
pulled from Pascal, writing a valid PDF. Getting there took four cfront fixes,
all in the "a `.c` compiled as a unit was a poorer relation of the same file
compiled as a program" family: file-scope globals were never reserved (an array
failed to lower; a **scalar silently read as 0**), their initializers never ran
(a unit has no `main` to run them at the head of, so pdfgen's tables stayed zero
and `pdf_create` returned NULL), a prototype ahead of its definition stayed a
dynamic import, and the crtl headers plus the C runtime stubs were only wired up
when the MAIN source was C — so `<stdarg.h>` came from the host and every
variadic C file failed. That last one is the second half of
[[bug-cfront-fegetround-unresolved-float-printf]], which had been closed on the
program-path repro alone.

Six shim units over it — `mimic_reportlab_pdfgen` (the canvas),
`mimic_reportlab_lib_colors` / `_units` / `_pagesizes` / `_utils`, and
`mimic_reportlab_pdfbase` (stringWidth from pdfgen's own metrics). Each states
its subset and raises outside it.

On the frontend side, dotted package imports (`from reportlab.pdfgen import
canvas`) and the `mimic_<module>` mapping landed with `--no-shims` to prove a
build used none, and `try/except ImportError` is now decided at compile time over
any try body that opens with an import — which is the shape the PIL guard uses.

**The blocker is [[decide-class-namespace-scoping]].** tkinter exports `Canvas`
and so does reportlab; the class namespace is flat and first-match, so the
shim's own constructor binds to tkinter's class and cannot see its own fields.
Preferring the current unit's class fixes that and breaks exception handling,
because pylib's and sysutils' `Exception` are one class only by virtue of
first-match. That attempt is written up and reverted in
[[bug-pascal-duplicate-class-name-silently-shadows]]. The sharpest edge is that a
qualified reference is first-match too: renaming the shim's class made
`canvas.Canvas(...)` bind silently to tkinter's `Canvas` and compile.

**Behind it**, with the collision worked around locally, `convertrawtext.py`
resolves every import and stops at `os.environ.get(...)` —
[[feature-rtl-environment-variables]]: nothing in the RTL can read the
environment at all.

**And at run time**, [[bug-c-unit-crashes-when-sysutils-is-used]]: `pdf_create`
segfaults when the program also uses sysutils, and passes under
`-dPXX_LIBC_HEAP`, so it is the pxx allocator rather than pdfgen. The heap bridge
itself is fine under the same conditions.

| module | wall |
| --- | --- |
| `key_analysis.py` | none — compiles and runs |
| `settings.py` | none — compiles, runs, builds all 60 widgets |
| `convertrawtext.py` | **compiles** (2026-07-28); runs into [[bug-nilpy-param-with-string-default-reads-garbage]] |
| `render_backend.py` | **compiles** as an import; standalone ends in "invalid symbol in lea" |
| `kadrv.py` | `import key_analysis` — the module loader landed; unverified since |
| `SongFormatter.py` | **compiles** (2026-07-28); runs into [[bug-heap-dict-literal-then-two-parses-corrupts]] |

## 2026-07-31 (Track B) — all five modules COMPILE; the app now gets as far as its session loader

Re-measured from the app's own directory, which is the only way a user would
invoke it:

| module | state |
| --- | --- |
| `key_analysis.py` | compiles and runs |
| `settings.py` | compiles |
| `render_backend.py` | compiles |
| `convertrawtext.py` | compiles |
| `SongFormatter.py` | **compiles and STARTS** — builds its window, then dies in `load_session()` |

Two things had to be true for that, and only one of them was about this app:

1. **`widget.destroy()`** briefly stopped dispatching, from a Track B rename the
   same day; reverted, see
   [[bug-lib-tkinter-trailing-underscore-params-block-kwargs]].
2. **The C headers.** Three of the five failed with `IR_UNSUPPORTED` near
   `va_list` — but ONLY when the compiler ran from `~/songformatter` rather than
   the pxx repo root. pxx's crtl include root resolves CWD-relatively for the
   shipped binary, so `<stdarg.h>` and `<math.h>` came from `/usr/include`,
   silently, with `M_SQRT2` becoming `0`. Filed as
   [[bug-crtl-headers-lost-when-cwd-is-not-the-repo-root]] (Track C). Passing
   `-Ilib/crtl/include …` is the interim; **any measurement of this app must
   pass it** or it is measuring glibc's headers.

### Where it stops now

`Unhandled exception: TypeError: expected a number, got object`, with no other
output. Located by bisecting the module's top-level statements and then
instrumenting a COPY (never the app):

```
top-level line 589   load_session()
  -> create_document_tab(...)          reached, FormatText built, notebook.add ok
     -> doc.set_document_text(...)     <-- raises here
```

The data path itself is clean — a separate probe reads `session.json` through
`Path.open` / `json.load` and walks all three documents' `text`, `file_path`,
`last_saved_text` and `is_dirty` with the right values. So the fault is inside
`FormatText.set_document_text` (`convertrawtext.py:1702`) or the
`convert_text()` it calls, not in the JSON or the façade's `add`.

Next step for whoever picks this up: instrument `set_document_text` the same way
and find which coercion sees an object. Do NOT edit the app to get past it.

### Found on the way, filed separately

[[bug-nilpy-module-level-name-bound-in-a-block-is-invisible-to-a-later-assignment]]
— at module level a name first bound inside `if`/`for`/`with` is "undefined
variable" on the RHS of a later top-level assignment. It hides in this app
because the same lines sit inside `def load_session()`, which is the working
case; a three-line probe reproduces it.
