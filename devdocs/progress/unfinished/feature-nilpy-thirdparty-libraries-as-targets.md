---
track: N
prio: 60
type: feature
status: unfinished
owner: frank2
---

# META: third-party Python libraries as pxx targets — classify, then compile

Every real Python application stops at its dependencies, so "can NilPy compile
an app" is really "can NilPy compile the libraries the app imports". This
ticket holds the **rule for classifying a dependency** and the **per-library
verdicts**; the actual work lands as child tickets in the owning lane.

Driving corpus: **neuzelaar** (`~/neuzelaar2`, `git@github.com:yoctobyte/neuzelaar.git`)
— a policy-first modular browser, 168 tracked `.py` / ~26.4k lines, **673 CPython
tests green in 12s**, three shells (headless / console / tk). It is the right
forcing target because its dependency set contains one of every class below.

**Design note: [`devdocs/dev/python-libraries.md`](../../dev/python-libraries.md)** —
the classification, the strategy ladder (compile-source > cpyext > bind-native >
mimic > own), the per-library RECIPE format, and the install policy (pip at
development time for source and oracle; nothing at run time). Read that first;
this ticket tracks the work.

## The classification (this is the whole point of the ticket)

A dependency is NOT "pure Python or C bindings". There are four kinds, and they
cost wildly different amounts:

| class | what it is | how to spot it | what pxx does |
| --- | --- | --- | --- |
| **1. pure Python** | ordinary `.py`, stdlib only | no `.so` in the installed package; wheel tag `py3-none-any` | **compile it as source, exactly like the app** — no new mechanism |
| **2. ctypes / cffi** | pure Python that `dlopen`s an ordinary C library. No `Python.h` anywhere | still no `.so` of its own, but imports `ctypes`/`cffi` | compile the C library with **cfront**, bind natively. Cheap, and it is the case pxx is unusually good at |
| **3. CPython C-API extension** | C/C++/Rust compiled against `Python.h`, calling `PyObject_*`; ships `_x.cpython-312-x86_64-linux-gnu.so`. Cython, PyO3 and pybind11 all land here | a `.so` in the package; wheel tag `cp312-manylinux_x86_64` | **the wall.** Either mimic the module's SURFACE in `lib/` (our own implementation behind the same API), or do without |
| **4. stdlib-C edge** | no bindings of its own, but leans on `re`, `zlib`, `json`, `hashlib`, `socket`, `ssl` — C inside CPython | plain imports | belongs in `lib/rtl` as OUR implementation. Not a per-library problem; it is the same list for every app |

**A wheel is a distribution format, not a build strategy.** It ships what
someone already built so the installing machine needs no compiler; it never
removes the native code. Its value to us is *triage*: the tag tells you the
class for free. `py3-none-any` = class 1 or 2. `cp312-manylinux_x86_64` = class 3,
and that artifact is CPython-3.12-ABI machine code we can never load. (An sdist
builds at install time — same classification, just deferred.)

Triage command, no reading required:

```sh
find <site-packages>/<pkg> -name '*.so' | head     # empty => class 1 or 2
grep -rlE '^[[:space:]]*(import|from)[[:space:]]+(ctypes|cffi)\b' <site-packages>/<pkg>
#   ^ anchored to an IMPORT on purpose: a plain `grep -rl 'ctypes\|cffi'`
#     matches the substring in `doctypeClass`, which is ordinary HTML-parser
#     vocabulary -- it misclassifies html5lib (class 1) as class 2. Measured
#     2026-08-14 on the neuzelaar venv; the corrected form reproduces every
#     verdict in the table below.
```

## Measured verdicts — neuzelaar's dependency set

Counted in `~/neuzelaar2/.venv/lib/python3.12/site-packages` on 2026-07-30:

| library | .so / .py | class | verdict |
| --- | --- | --- | --- |
| `html5lib` | 0 / 33 | 1 | compile as source. The HTML parser — the biggest single win |
| `tinycss2` | 0 / 10 | 1 | compile as source |
| `webencodings` | 0 / 5 | 1 | compile as source (both of the above depend on it) |
| `js2py` + `pyjsparser` | 0 / 94 + 0 / 4 | 1 | compile as source; optional dep |
| `quickjs` | 0 / 1 (not built here) | 3 when built | optional; pxx already has a QuickJS corpus ticket on the **C frontend** side — the C source is ours to compile, the CPython glue is not |
| `Pillow` | **8 / 97** | **3** | the only true wall. See below |

So the fear that "html5lib blocks us" is backwards: html5lib is the easy case,
and the same job as neuzelaar itself, just more source.

## Pillow — the one real wall, and why it is narrower than it looks

`PIL/_imaging.so` links `libjpeg`, `libtiff`, `libopenjp2`; `_imagingcms` links
`liblcms2`. Note the split: **the codecs are ordinary C** (cfront territory);
only the glue that turns them into `PIL.Image` objects is C-API.

And neuzelaar already isolates it behind three seams:

- `neuzelaar/engines/image/pillow_adapter.py` — `decode_image_info` /
  `decode_image_bitmap`, a narrow decode interface (`Image.open`, size, mode)
- `neuzelaar/render/software.py` — `Image.new` / `frombytes` / `ImageDraw` /
  `ImageFont`, i.e. a raster canvas
- `neuzelaar/shells/tk/shell.py` — `ImageTk` for display only

That is a *mimic-able* surface, not the whole of Pillow, and the raster-canvas
half overlaps what `lib/pcl` already does for PDF. Filing the decision as its
own fork below rather than guessing.

## Stdlib surface neuzelaar needs (class 4 — the real recurring cost)

`argparse base64 collections concurrent contextlib contextvars dataclasses
datetime enum functools hashlib http importlib io itertools json math os
pathlib queue random re signal subprocess sys threading time tomllib traceback
typing urllib uuid xml`

This list, not the third-party packages, is the honest measure of the work. It
is also reusable: every future app wants most of it.

## RE-BASELINED 2026-08-14 — the section below replaces the 2026-07-30 probe

**Both items the old plan scheduled were already done**, and nothing said so.
Measured at HEAD:

- `from __future__ import annotations` compiles and runs. So do all nine feature
  names (`division`, `print_function`, `generator_stop`, `unicode_literals`,
  `absolute_import`, `nested_scopes`, `with_statement`, `barry_as_FLUFL`), each
  matching CPython.
- `@dataclass` works, including the generated `repr`: `Point(x=1, y=2)`,
  identical to CPython.

That is the important finding about this ticket, more than any number below: a
schedule written into prose, in a repo whose compiler moves daily, goes stale
without emitting a signal. Acting on it would have meant implementing solved
problems. **The step list is therefore deleted rather than updated** — the
census is a command now, not a paragraph.

### Census — 168 git-tracked files, 26,408 lines, compiled with HEAD

**18 compile (11%).** The 150 failures, bucketed by KIND, which is the number
that actually schedules work:

| failure kind | files | lane |
| --- | --- | --- |
| **intra-project imports** (the app's own modules) | **89** | N — one mechanism |
| stdlib imports (`enum`, `argparse`, `datetime`, `contextlib`, `threading`, `importlib`) | 28 | class 4, `lib/` |
| third-party imports (`pytest`, `yaml`, …) | 19 | mostly test-only |
| language / frontend gaps | 14 | N |

**The old plan's premise is wrong.** `@dataclass` was said to "decide the
schedule"; it is **5 files**. The schedule is decided by intra-project imports at
**89**, and they are ONE defect, not 89:
[[feature-nilpy-dotted-imports-resolve-to-source-files]] — a dotted import
resolves only to a hand-written `mimic_*` shim and never looks for the source
file on disk. Flat sibling imports (`from bus import Bus`) already work, for
`.py` and `.npy` alike; only the dotted form is missing. Verified on a clean
purpose-built package, and ruled out as a masked compile error.

**The language-gap column is a lower bound.** A file that fails on its first
import is never compiled, so its remaining constructs were never exercised. Expect
14 to grow once imports resolve — an argument for fixing imports first.

The full language-gap list as it stands (small, and mostly typing-shaped):
dataclass `field(default_factory=...)` (2), unsupported parameter type
annotation (4), `@dataclass frozen=True` (1), unsupported dataclass field type
(3), `run has no parameter named 'X'` (2), undefined `Union` / `process_time`.

### Dependency set — unchanged since 2026-07-30

`.so`/`.py` counts re-measured in the venv and identical, so the verdict table
above still holds. One correction, to the *triage command* rather than to any
verdict: the documented `grep -rl 'ctypes\|cffi'` matches the substring in
`doctypeClass`, ordinary HTML-parser vocabulary, and misclassifies **html5lib**
as class 2 when it is class 1 — the difference between "the biggest single win"
and work that does not exist. Fixed here and in `devdocs/dev/python-libraries.md`
by anchoring to an import statement.

### Reproducing this

**The method, the traps and the lesson are written up in
[`devdocs/dev/python-libraries.md`](../../dev/python-libraries.md) §7 — read that
rather than this summary.** Two traps in brief, because both produced confident
wrong numbers before being caught:

1. **Census the GIT-TRACKED files.** An `os.walk` of `~/neuzelaar2` picks up a
   vendored Web Platform Tests corpus — **549** files of third-party fixtures —
   and yields a clean-looking histogram of the wrong population (`wptserve_utils`,
   `sec-ch-ua.py`). `git ls-files '*.py'` is what defines the corpus, and it
   returns exactly the ticket's 168 files / 26.4k lines.
2. **Print incrementally.** A serial run that only summarises at the end dies on
   a wall-clock cap with nothing to show.

### Open — needs a decision before this campaign files more children

The corpus lives at `~/neuzelaar2`, **outside this repo**. No tier can run it, no
tstate report can regress it, and every number above is a claim only this machine
can check. Tolerable for exploration; not tolerable for a campaign that schedules
work. Either vendor a representative subset into `test/` (a few hundred lines
covering the census's top constructs) or state explicitly that this stays a local
exploration whose findings must be re-derived as ordinary `.npy` tests before
they gate anything. Not guessed at here — filed for the user.

## Plan

Steps 1 and 2 of the previous plan (`__future__`, `@dataclass`) are **done** —
see the re-baseline above; both were already working when measured, which is why
this list no longer carries per-construct steps. **Regenerate the next step from
a census run, do not read it from here.**

The ordering that survives, because it is strategy rather than a construct list:

1. **[[feature-nilpy-dotted-imports-resolve-to-source-files]]** — a dotted import
   must find the source file on disk, not only a `mimic_*` shim. 89 of 150
   census failures, one mechanism, and nothing multi-module compiles until it
   lands. Everything below is blocked on it in practice.
2. **Class-4 stdlib surface**, by census frequency rather than by guess: `enum`,
   `argparse`, `datetime`, `contextlib`, `threading`, `importlib` are what this
   corpus actually reaches for (28 files). This is the reusable half — every
   future app wants most of it — and it is `lib/` work, not frontend work.
3. Compile `webencodings` → `tinycss2` → `html5lib` **bottom-up as standalone
   corpora**, each with its own upstream test suite as the oracle. A library
   that compiles and passes its own tests is a permanent asset, not just a
   step toward neuzelaar.
4. Then neuzelaar headless (`python -m neuzelaar <url>`), with its 673 tests as
   the differential oracle.
5. tk shell last — it is the widest surface and the least diagnostic.

Do **not** rewrite any of these libraries to Pascal. The mission is compiling
the real source as-is; a rewrite proves nothing (see the mission note).

## DECIDED 2026-07-31 (user, Track U) — compile the C SOURCE, never load a wheel

**Verdict: the CPython C-API is supported by compiling the extension's C
SOURCE with cfront against OUR OWN `Python.h`** (option 2.c below). Dynamic
loading of a prebuilt `.so` (2.b) is REJECTED, permanently. Mimicking a
module's surface in `lib/` is a stopgap for a blocked milestone, not the
strategy.

The reasoning, recorded so it does not get relitigated:

- A `cp312-manylinux_x86_64` artifact is machine code pinned to one CPython
  version's ABI on one architecture. Loading it would require pxx to BE
  CPython — real `PyObject` layout, refcount semantics, `tp_*` slots, the GIL —
  and it would still yield nothing on any cross target. Every dependency would
  re-open the version question.
- Compiling the SOURCE against our own `Python.h` uses OUR ABI: no CPython
  version pinning, works on every backend, and **the extension links into a
  STATIC BINARY**. That is the outcome we want and the one thing a wheel can
  never deliver.
- It generalises. Cython-, PyO3- and pybind11-generated modules all emit
  C/C++ against the same API, so one layer unlocks a large fraction of the
  ecosystem — "just compile the library" is a killer feature that stays
  useful forever, which no per-library mimic ever is.

**Scope correction that follows from this:** neuzelaar is NOT a goal. It is one
random test target that happens to exercise all four dependency classes. The
goal is compiling Python libraries. Judge progress by libraries that compile
and pass their own upstream suites, not by neuzelaar milestones.

**And Pillow stops being special.** Under this verdict its own C sources are
compiled like any other class-3 package; only the C libraries BENEATH it
(libjpeg/zlib/lcms2 — plain C, no `Python.h`) are cfront corpus work. The
`mimic_PIL` idea survives only as a stopgap if an image-dependent milestone is
blocked while cpyext is still young.

Child: [[feature-nilpy-cpyext-c-api-from-source]].

## Forks (1 open; 2 is decided above)

- `decide-image-stopgap-while-cpyext-is-young` — narrowed by the verdict above.
  The END STATE is settled (compile Pillow's own C via cpyext, its underlying
  libjpeg/zlib via cfront). Open only: while cpyext does not exist yet, does an
  image-dependent milestone get a `mimic_PIL` stopgap, or does it simply wait?
  Cheap either way; ask only when something is actually blocked on it.
- ~~`decide-cpython-c-api-support`~~ — **DECIDED, see above: compile the source
  (2.c), never load a wheel (2.b).**
- where do compiled third-party libraries LIVE? A vendored corpus dir vs
  compiling from the user's site-packages in place. Affects how the frontend
  resolves `import html5lib`.

## Children (file as they start)

- [[feature-nilpy-cpyext-c-api-from-source]] — the strategic one
- [[feature-nilpy-future-import-noop]]
- [[feature-nilpy-dataclasses]]
- [[feature-nilpy-corpus-html5lib]]
- [[feature-nilpy-corpus-neuzelaar]]

## 2026-08-09 — plan steps 1 and 2 done; step 3 STARTED on webencodings

**Step 1, `__future__`, DONE.** `from __future__ import annotations` is now a
no-op, as it should be — NilPy never evaluates annotations, which is what the
import asks for. It was line 1 of 86 of the 168 corpus files.

**Step 2, `@dataclass`, advanced.** The decorator generates `__repr__` as well
as `__eq__` now (`print(p)` printed the instance HANDLE before). Remaining and
filed: a `str` field's DEFAULT is dropped —
`bug-nilpy-dataclass-str-field-default-is-dropped`.

**Step 3, webencodings — first real measurement.** It is 5 files / ~1100 lines,
pure Python, with its own test suite, and it is the bottom of the
`webencodings -> tinycss2 -> html5lib` stack this ticket prescribes.

- `labels.py` — a 214-entry table — **COMPILES AND RUNS**, and
  `from labels import LABELS; print(len(LABELS))` answers 214. A real library's
  data module, compiled as source, correct.
- **RELATIVE IMPORTS were the first wall and are now FIXED.**
  `from .labels import LABELS` failed with "expected a module name after from" —
  the leading dot was not handled at all. Every real package uses them
  internally, so this walled compile-the-source at the first library. All the
  spellings work now: `from .mod import a, b`, a class through one, `as`
  aliasing, `from . import mod` with qualified access, and two different
  relative imports in one file. Pinned by `test/test_nilpy_relative_import.npy`.
- **`import codecs` is the next wall**, and it is a real one rather than a
  parse gap: webencodings is *about* codecs, so it needs an actual `codecs`
  shim. That is Track B (a `mimic_codecs` unit), and it is the honest next
  item for this step — filed below.

The order of these findings is worth keeping: the parse-level walls
(`__future__`, relative imports) were cheap and unblocked everything behind
them; the remaining wall is a genuine missing stdlib module, which is the
"class 4 — stdlib-C edge" row of this ticket's own table and the recurring cost
it predicts.

### Ranked walls over the whole stack, measured 2026-08-09

Compiled every `.py` of `webencodings` (5), `tinycss2` (10) and `html5lib` (33)
as source and ranked what stopped each file. Two of the walls were LANGUAGE gaps
and are now fixed; everything else is a missing MODULE.

**Fixed here:**

- **backslash line continuation** — `error: unexpected character: \`, in 6 of
  html5lib's 33 files, all the same shape (`if a and \` split across lines).
  Handled exactly as an open bracket is: no NEWLINE token, no indentation
  processing on the next line. It needed a second fix for ADJACENT STRING
  LITERALS across a continuation, whose rule was keyed on paren depth alone —
  `"x" \` + `"y"` quietly evaluated to just `"x"`, a silent half-value.
- **`class C(object):`** — Python 2's explicit new-style spelling, still common.
  A no-op in Python 3, so the class registers with no parent. Consumed rather
  than resolved: inventing an `object` class would put a real base in the chain
  for `super()` and the method tables to explain.
- **relative imports** (above).

**Everything still failing is `import <module not present>`**, which is this
ticket's own "class 4 — stdlib-C edge" cost rather than a language gap:

| missing module | files blocked |
| --- | --- |
| `six` | 11 |
| `base` / `_utils` (html5lib's own, via relative imports inside subpackages) | 5 |
| `xml.dom` / `xml.sax` | 5 |
| `warnings` | 3 |
| `genshi` (an optional treewalker) | 2 |
| `codecs` | 2 |

**`six` is the single biggest lever** — 11 files. It is a tiny pure-Python
compatibility shim (`PY3`, `text_type`, `string_types`, `iteritems`, …) and
almost all of it is trivially true on a Python-3-only dialect, so a `mimic_six`
is a small Track B job with a large unblock. `warnings` is nearly as cheap (a
`warn()` that prints to stderr). Those two plus `codecs` would take html5lib
from 1/33 to most of the way.

Worth stating plainly, because the file counts read worse than the reality: a
file is rejected at its FIRST unavailable import, so one missing module hides
however many language gaps are behind it. The two language walls above were only
visible because they happened to sit in files whose imports all resolved.

## Re-scan 2026-08-09 (Track B) — real sources, current pin

The three packages are now fetchable — `tools/install_lib_candidates.sh
nilpy-stack` (webencodings v0.5.1, tinycss2 v1.5.1, html5lib 1.1, pinned). So
the scan is reproducible rather than dependent on whatever happened to be
installed on one box.

48 non-test `.py` files, compiled one at a time with the pinned compiler at
`0250202db`. **4 compile, 44 wall.** Ranked by first wall:

| first wall | files |
| --- | --- |
| `import: no unit named six and no shim mimic_six` | 13 |
| `import: no unit named webencodings and no shim mimic_webencodings` | 6 |
| `undefined variable (iter)` | 5 |
| `import: no unit named warnings and no shim mimic_warnings` | 3 |
| `import: no unit named xml_dom and no shim mimic_xml_dom` | 3 |
| `import: no unit named genshi_core and no shim mimic_genshi_core` | 2 |
| `import: no unit named xml_sax_xmlreader and no shim mimic_xml_sax_xmlreader` | 2 |
| `import: no unit named codecs and no shim mimic_codecs` | 2 |
| `unexpected token` | 1 |
| `import: no unit named _utils and no shim mimic__utils` | 1 |
| `import: no unit named constants and no shim mimic_constants` | 1 |
| `Nil Python: unknown base class Mapping` | 1 |
| `import: no unit named colorsys and no shim mimic_colorsys` | 1 |
| `undefined variable (MULTILINE)` | 1 |
| `import: no unit named urllib_request and no shim mimic_urllib_request` | 1 |
| `undefined variable (lookup)` | 1 |

### Two walls from the earlier scan are GONE

An identical scan a few hours earlier, against the previous pin, had
`__future__` second with **8 files** and backslash-continuation with **3**. Both
are zero now — v252 fixed them. (That is also a caution: the pin moved
underneath a running scan and the two runs disagreed until the compiler sha was
pinned down. Any scan result here should name the sha it came from.)

### What the ranking actually means

- **`six` (13)** is blocked on class/type-as-value, not on writing a shim —
  [[feature-nilpy-six-and-warnings-shims]] has the measurement.
- **`webencodings` (6)** is INTRA-STACK: tinycss2 and html5lib importing the
  package below them. Not a stdlib gap — it needs `import webencodings` to
  resolve to the fetched source, i.e. the T3 module loader.
- **`iter` (5)** is a missing builtin, and the cheapest item on this list.
- **`codecs` (2)** is small in file count but it is the KEYSTONE: it is the only
  thing blocking `webencodings/__init__.py`, the bottom of the stack.


## MEASURED 2026-08-13 — webencodings is class **4**, not class 1. The verdict table was wrong.

Compiled the three modules of the installed `webencodings` directly with pxx at
HEAD, which is cheaper than reading them:

| module | result |
| --- | --- |
| `labels.py` (the 200+ label -> encoding map) | **compiles clean** |
| `__init__.py` | `no unit named codecs` |
| `x_user_defined.py` | `no unit named codecs` |

The `.so` triage this ticket teaches is right about the wheel tag and wrong
about the cost here: webencodings ships no native code of its own, so the
`find … -name '*.so'` probe calls it class 1 — but it is a **thin wrapper over
CPython's codec registry**, which is C inside CPython. That is class 4, "the
real recurring cost", and it means the bottom of the dependency ladder
(`webencodings -> tinycss2 -> html5lib`) starts one rung lower than the plan
assumes: **`codecs` before webencodings**.

The surface it actually needs, measured (nothing else):

```
codecs.lookup / codecs.register / codecs.CodecInfo
codecs.charmap_build / charmap_decode / charmap_encode
codecs.Codec, IncrementalDecoder, IncrementalEncoder, StreamReader, StreamWriter
```

That is small and concrete — the charmap trio plus a registry and five base
classes — and every one of them is OUR implementation to write in `lib/`, once,
for every future app. It is also **not** a per-library problem, which is exactly
what this ticket's class-4 row predicted; the correction is only about which
class webencodings is in.

The triage command in this ticket should therefore gain a second line: a package
with no `.so` is class 1 **only if it also imports nothing C-backed** — grep its
imports against the stdlib-C list (`codecs re zlib json hashlib socket ssl`)
before calling it cheap.

## The html5lib ladder's stdlib bill, MEASURED 2026-08-13

Collected every `import` across `six.py`, `webencodings/`, `tinycss2/` and
`html5lib/` (the ladder this ticket plans), then tried each one as a one-line
`.npy` against HEAD. This is the class-4 cost in numbers rather than in
principle:

```
present today:  collections io itertools json math re sys types
MISSING:        bisect codecs copy functools operator string warnings weakref xml
```

(Third-party names in that sweep — `genshi`, `lxml` — are optional treewalker
backends html5lib imports lazily; `webencodings` and `six` are the ladder
itself.)

So **nine** stdlib modules stand between HEAD and html5lib, and the ordering
falls out of the ladder:

1. `functools itertools operator` — `six.py` stops at its first import
   (`functools`, line 25) and needs these three plus `sys`/`types`, which are
   present. six is 1003 lines of pure Python and is html5lib's FIRST wall.
2. `codecs` — webencodings ([[feature-b-mimic-codecs-for-nilpy]], surface
   already measured).
3. `string` — html5lib/constants.py (and see
   [[bug-nilpy-python-import-resolves-against-c-headers]]: `import string`
   used to resolve to `/usr/include/string.h`, which is why this was invisible).
4. `copy warnings weakref bisect xml` — the rest of html5lib.

None of these is a per-library problem: the same nine serve every future Python
app, which is the point the class-4 row of this ticket already makes.

## RE-SCANNED 2026-08-14 at sha 618371ac3 — the ranking above is stale

Same method as the 2026-08-09 scan, against the fetched pinned sources
(`tools/install_lib_candidates.sh nilpy-stack`): every non-test `.py` of
`webencodings` + `tinycss2` + `html5lib` compiled one at a time, ranked by its
FIRST wall. **58 files, 8 compile.**

| first wall | files |
| --- | --- |
| `no unit named six` | 13 |
| **COMPILES** | **8** |
| `no unit named webencodings` | 6 |
| `no unit named xml_dom` | 3 |
| `no unit named warnings` | 3 |
| `no unit named codecs` | 3 |
| `no unit named xml_sax_xmlreader` | 2 |
| `no unit named genshi_core` | 2 |
| `no unit named constants` | 2 |
| `no unit named html5lib` / `tinycss2` / `pyperf` / `_utils` / `urllib_request` / `colorsys` / `argparse` / `setuptools` / `docutils` | 1 each |
| `undefined variable (MULTILINE)` | 1 |
| `undefined variable (os)` | 1 |
| `undefined variable (python_implementation)` | 1 |
| `unknown base class Mapping` | 1 |
| a NESTED loop target (`for n, (p, q) in ...`) | 1 |

### What changed since 2026-08-09, and it is worth stating

The three LANGUAGE rows that scan reported are **gone**: `undefined variable
(iter)` (5 files), `undefined variable (lookup)` (1) and `unexpected token` (1).
`iter`/`next` were the scan's own "cheapest item on this list" and they are in.

**Everything blocking the ladder now is a missing MODULE except five files.**
That is the class-4 "stdlib-C edge" cost this ticket's table predicted, and it
is Track B shim work, not Track N language work — so the honest read is that
**Track N is no longer the bottleneck for this ladder.**

### The five remaining LANGUAGE rows, and where they belong

- **a NESTED loop target** — `for n, (p, q) in ...`. Ordinary Python, refused
  with a clear diagnostic. The one genuine Track N item on this list.
- **`unknown base class Mapping`** — `collections.abc`. A module, wearing a
  language diagnostic.
- **`MULTILINE` / `os` / `python_implementation`** — bare names that should have
  come from `re` / `os` / `platform`; module surface, not syntax.

### Provenance

The compiler was a self-hosted fixedpoint build at **618371ac3**, and it was NOT
rebuilt during the run — worth recording because the 2026-08-09 note in this
file documents two scans disagreeing precisely because the pin moved underneath
one of them.

### Track N's own contribution since the last scan

`bug-n-a-type-name-is-not-a-first-class-value` shipped (pins v287-v289): builtin
types and `type(x)` are values now, which is what
[[feature-nilpy-six-and-warnings-shims]] was blocked on. Measured directly
against pip's vendored `six.py` (998 lines): it clears its whole language
surface and stops at **line 25, `import functools`**. So `six` — 13 of these 58
files — is now purely a shim job.

## RE-SCANNED 2026-08-14 (second run, same day) at sha c61b43390

Same method and same 58 files as the scan above, re-run after this session's
Track N landings (nested loop and assignment targets; the character-string
surface; `str` as an iterable argument). **8 compile, unchanged; the ranking of
walls is unchanged in shape.**

The one thing that moved is the row this file called "the one genuine Track N
item on this list":

- **`a NESTED loop target (for n, (p, q) in ...)` — GONE.** Landed with
  `feature-nilpy-starred-and-nested-unpacking`. `html5lib/_trie/_base.py` now
  reaches a different, further wall (`unknown base class Mapping`).

So the five language rows are four, and **every one of them is module surface
wearing a language diagnostic**:

| row | what it really is |
| --- | --- |
| `unknown base class Mapping` | `collections.abc` |
| `undefined variable (MULTILINE)` | `re` |
| `undefined variable (ascii_lowercase)` | `string` |
| `undefined variable (python_implementation)` | `platform` |
| `undefined variable (os)` | `os` (a Sphinx `docs/conf.py`, not library code) |

**The conclusion the previous scan drew now has no exceptions at all: nothing on
this ladder is blocked on the NilPy LANGUAGE.** 50 of 58 files stop at a missing
module, and the remaining 4 stop at a missing module's *name*. That is Track B
shim work — `six` alone is 13 files and is already measured as pure shim
(`feature-nilpy-six-and-warnings-shims`).

### Provenance

Compiler was a self-hosted fixedpoint build at `c61b43390`, not rebuilt during
the run (the 2026-08-09 note in this file records two scans disagreeing because
a pin moved underneath one of them). Raw per-file results are reproducible with
the same one-file-at-a-time loop over
`library_candidates/{webencodings,tinycss2,html5lib}`.

### What this means for the plan

Plan step 3 ("compile webencodings → tinycss2 → html5lib bottom-up") is not
waiting on Track N. It is waiting on the class-4 stdlib surface this ticket's
own table predicted would be "the real recurring cost", and that prediction has
now been measured twice. A Track N agent taking `next --track N` will keep
landing language work that this ladder does not need; the ladder needs shims.

## 2026-08-15 (Track B) — the codecs rung is BUILT, and webencodings still does not compile

`lib/rtl/mimic_codecs.pas` landed ([[feature-b-mimic-codecs-for-nilpy]]):
`import codecs` resolves, the charmap trio round-trips **byte-identically to
CPython** on webencodings' own x-user-defined table, and the registry answers
`lookup`/`register`/`CodecInfo`. That was the class-4 gap this ticket predicted
would be the recurring cost, and building it took a few hours.

Then the two webencodings files were compiled again, and the prediction above
needs one correction: **the ladder was not only waiting on shims.** With the
shim in place, each file stops on a distinct NilPy *language* gap:

| file | now stops at |
| --- | --- |
| `labels.py` | nothing — compiles (unchanged) |
| `x_user_defined.py` | [[bug-nilpy-class-named-after-its-imported-base-hangs-the-compiler]] — `class Codec(codecs.Codec)` makes the compiler LOOP FOREVER, then [[bug-nilpy-multiple-inheritance-from-an-imported-base-is-refused]] |
| `__init__.py` | [[bug-a-bytes-has-almost-none-of-its-python-methods]] — `b.lower()`, and `b.startswith()` on the next line |

None of the three is a missing module. Two are Track N language bugs and one is
Track A (`TPyBytes` in `compiler/builtin/pylib.pas`), and all three are the kind
that every stdlib-shaped Python module hits, not webencodings quirks — `class
X(mod.X)` is how all ~100 of CPython's own `encodings/*.py` are written.

So the corrected reading: the scan measured *the first* wall per file, and a
shim only reveals the next one. "50 of 58 files stop at a missing module" stays
true and stays the biggest single lever; it is just not the whole distance.
Worth re-running the scan after each shim lands rather than treating the
original table as the remaining work.

## 2026-08-17 — measured: the surface is FETCHED and WIRED TO NOTHING

Counted Makefile references per corpus, against `library_candidates/` presence.
Every tree below is present on disk.

| corpus | frontend | Makefile refs |
| --- | --- | ---: |
| lua | C | 56 |
| sqlite | C | 46 |
| chess | C | 31 |
| quickjs | C | 25 |
| zlib | C | 21 |
| cjson / csmith / duktape | C | 15 / 14 / 14 |
| c-testsuite / tcc | C | 9 / 8 |
| fcl-json | P | 9 |
| **html5lib / reportlab** | **N** | **1 / 1 — both COMMENTS, not rules** |
| **webencodings / tinycss2** | **N** | **0 / 0** |
| fpc-testsuite | P | 0 |

**The C frontend built corpus discipline; NilPy did not.** That is the whole
finding, and it explains a shape that otherwise looks like bad luck: N took 628
of 1751 track-tagged commits in the last 30 days (38%) while the only body of
genuinely independent Python on the box was exercised by nothing.

## Why this matters more than the open bug count

The 17 open N bugs all came from surfaces we chose — our own `.npy` tests, and
uforth, which is OUR code (see the provenance note: its value is semantic DEPTH
under an external conformance suite, not language-surface BREADTH). Code written
here can unconsciously avoid what NilPy does not support, so "it compiles" proves
less than it looks.

`webencodings`, `tinycss2`, `html5lib` and `reportlab` are the only Python on
this machine that we could not have shaped to fit. Wiring them is what converts
"we think we are on par with CPython" into a measured claim — and it will find
the class of defect the current 17 cannot contain, precisely because nobody here
chose the constructs.

## Precedent to copy, so this is not a design job

C's corpus pattern is mature and directly reusable: vendor pinned via
`tools/install_lib_candidates.sh` (already done for all four), a Makefile target
per corpus, run the library's OWN test suite as the oracle, reduce each failure
to a minimal repro against CPython, fix one, add a regression test. See the lua /
quickjs / duktape targets for the shape.

Expected outcome worth stating up front: **the open-bug count will RISE.** That
is the intended result, not a regression — it is the same trade the C corpora
made, and it is why C's frontend now has 3 open bugs against N's 17.

---

## 2026-08-17 (frank2, Track N) — started on webencodings; the FIRST blocker is relative imports

Confirmed the measurement independently before starting: `grep -c` in the
Makefile gives webencodings 0, tinycss2 0, html5lib 1, reportlab 1 against
lua 56 / sqlite 46 / quickjs 25 / zlib 21. All four Python trees are present
under `library_candidates/`.

### Module resolution already works — via `-Fu`, not `sys.path`

First attempt used `sys.path.insert(0, ...)` as CPython does. That is a RUNTIME
concept and pxx resolves imports at COMPILE time, so it cannot work and should
not be expected to. The working spelling is the Pascal unit-search flag:

```sh
./compiler/pascal26 -Fu<abs path to package root> drv.npy drv
```

(or running with the package root as cwd). With that, `from webencodings import
lookup, decode, encode, UTF8` **resolves the package and begins compiling its
`__init__.py`** — it is not a "no module named" failure at all. Worth recording
because `-Fu` is not in the compiler's usage line.

Bonus confirmation: the compile emits `note: codecs -> mimic_codecs (shim,
subset)`, so the `mimic_codecs` shim written earlier this session is doing real
work on genuinely third-party code rather than only on our own tests.

### The blocker: `from .sub import NAME` is not parsed

`webencodings/__init__.py:19` is `from .labels import LABELS` and the compile
dies there. Reduced to five lines, no third-party code involved:

```
pkg/sub.py        VALUE = 7
pkg/__init__.py   from .sub import VALUE
main.npy          from pkg import VALUE
                  print(VALUE)
```

| | |
| --- | --- |
| CPython | `7` |
| pxx | `pascal26:1: error: undefined variable (from)` |

The leading dot is what breaks it — plain `from pkg import VALUE` parses fine.

**This blocks all four corpora, not just webencodings.** An intra-package
relative import in `__init__.py` is how essentially every real Python
distribution is laid out, so nothing further can be measured until it works.
That makes it the true first rung, ahead of "wire a Makefile target" — a target
wired today would only assert the same parse error.

Filed as [[bug-n-relative-import-from-a-package-is-not-parsed]].

### Note on what this says about the ticket's premise

The premise — that our own `.npy` tests and uforth cannot surface what we do not
support, because we unconsciously write around it — is confirmed on the very
first contact. Relative imports are unavoidable in third-party layout and
completely avoidable in a single-file test, which is exactly why 17 open N bugs
and 628 commits in 30 days never hit it.

### 2026-08-17 (cont.) — the relative-import blocker is CLEARED; the next two rungs are named

Fixed and pushed (`a6d84f1c6`). Both forms now work where real packages write
them — inside a package's `__init__.py`, which is a different parser path from
the main program's leading import run, and the reason a green
`test_nilpy_relative_import.npy` had been asserting the wrong position all
along. Details, including why the previously-recorded three-step ordering
turned out to be one change at two sites, are in
[[bug-n-relative-import-from-a-package-is-not-parsed]].

`webencodings/__init__.py` now compiles **past line 19 to line 50**.

**The ladder's next two rungs, both found by walking one rung further:**

| rung | wall | lane |
| --- | --- | --- |
| 1 (done) | relative imports in `__init__.py` | N |
| 2 | a package does not re-export what its `__init__.py` imports — [[bug-n-a-package-does-not-re-export-what-its-init-imports]] | **N** |
| 3 | `codecs.CodecInfo` (webencodings:50) — `mimic_codecs` surface | **B** |

Rung 2 is the one that matters most and was invisible until now: importing the
public names out of private modules in `__init__.py` is *the* way a Python
package publishes an API, and all three fetched libraries do it. A corpus driver
doing `from webencodings import lookup` meets it the moment the file compiles.

Also found, and it is the dangerous kind: **`from mod import NAME as ALIAS`
binds 0 inside a pulled module**, silently
([[bug-n-from-import-as-alias-binds-zero-inside-a-pulled-module]]). Caught only
because a probe's sum printed 5 where CPython printed 6.

**This is the second and third confirmation of the ticket's premise in one
session.** All three defects are invisible to a single-file `.npy` test — one
needs a package boundary to cross, one needs a module to be pulled rather than
run. 628 N commits in 30 days never touched them because nothing here had a
package.

**Still true that the Makefile targets are not yet wired.** Wiring one today
would assert rung 2's failure rather than a corpus result, so the order stands:
fix rung 2, then wire `webencodings` as the first N corpus target with its own
test suite as the oracle.

### 2026-08-17 (cont.) — rungs 1 and 2 both landed; they were ONE mechanism

Pushed: `a6d84f1c6` (relative imports in a package `__init__.py`), `85c0801ea`
(an aliased import binding 0 inside a pulled module), `63d80e8fc` (a package
re-exports what its `__init__.py` imports). Gate green on each.

The two rungs listed above as separate work turned out to share a root, and the
sequencing was forced rather than chosen:

- **The alias bug was not a parse defect.** `PyFlushImportAliases` had exactly
  one call site, in the main-program path; `ParsePyModule` never called it. So a
  module's alias symbol was allocated — which is why it resolved instead of
  erroring — and its `ALIAS = NAME` assignment was never emitted. Silent 0.
- **Re-export is the same missing binding.** The deciding measurement is that an
  *aliased* re-export already worked while the plain one did not: same units,
  same visibility, opposite results. The alias makes a real symbol in the
  importing unit; the plain form made none and leaned on flat unit scope, which
  stops at the module boundary.

So the ticket's fork — "make `uses` transitive, or bind the name?" — dissolved
without needing a Track U decision, and `VisibilityAllows` (Track A ground, and
deliberately non-transitive since 2026-08-15) was never touched. Binding is also
just what CPython does: a from-import binds in the importer's namespace rather
than opening a window onto the exporter's.

**Method note, and it is the second one today.** Both fixes came from running the
CONTROL in the spelling the ticket was not about — the absolute form, the
aliased form — and in both cases the control is what identified the variable.
The relative-import ticket's staged three-step plan and this ticket's design
fork were each derived from a real observation and each dissolved on one extra
measurement. Banked *observations* held up all day; banked *conclusions* did not.
Worth marking which is which when writing these up.

### Where the ladder stands

| rung | status |
| --- | --- |
| relative imports in `__init__.py` | **done** (N) |
| a package re-exports its imports | **done** (N) |
| `codecs.CodecInfo` — `mimic_codecs` surface | **open, Track B** — webencodings:50 |
| a subpackage DIRECTORY resolving as a module | **open, N** — [[bug-n-a-subpackage-directory-does-not-resolve-as-a-module]]; html5lib only (it has `_trie`, `treebuilders`, `treewalkers`), so it is that library's rung, not webencodings' |

webencodings sat at line 50 before these fixes and sits at line 50 after — which
is the point worth recording. It confirms the fixes moved the wall they were
aiming at and left the one they were not.

### LADDER RE-SCAN 2026-08-17 at `63d80e8fc`, A/B'd against the pin — 58 files

Method changed from the earlier scans in this file and the numbers are therefore
**not comparable to them**: every file is compiled with
`-Fulibrary_candidates/<root>` so its intra-package imports resolve. Earlier
scans did not pass `-Fu`, which is why they report more "no unit named
<sibling>" and fewer deep walls. Stating it because a bare count from this table
next to a bare count from the 2026-08-14 one reads as a regression and is not.

Run twice — once with the pinned compiler (`47836e63`), once at HEAD — so the
three fixes that landed today could be A/B'd rather than asserted.

| | pinned | HEAD |
| --- | ---: | ---: |
| compile | **4** | **4** |
| files whose wall MOVED | — | **2** |
| files that REGRESSED | — | **0** |

The four that compile are the same four in both runs:
`webencodings/labels.py`, `webencodings/x_user_defined.py`,
`html5lib/filters/base.py`, `html5lib/filters/__init__.py`.

Both changed files improved, and both are the relative-import fix:

| file | pinned | HEAD |
| --- | --- | --- |
| `webencodings/__init__.py` | `undefined variable (from)` | `undefined variable (CodecInfo)` |
| `tinycss2/docs/conf.py` | `undefined variable (from)` | `no unit named webencodings` |

**So: no library file compiles today that did not compile this morning.** Three
frontend fixes landed and the compile count is flat; what they bought is two
walls moved deeper. That is the honest read and it should be the headline,
because "three bugs fixed" and "the ladder advanced" are different claims and
only the first one is true.

### The ranking, and why Track N is not the lever

| first wall | files |
| --- | ---: |
| `no unit named six` | **15** |
| `no unit named webencodings` (intra-stack) | 7 |
| COMPILES | 4 |
| `class Filter cannot inherit from itself` | 3 |
| `no unit named xml_dom` | 3 |
| `no unit named warnings` | 3 |
| `unexpected character` (non-UTF8 fixtures) | 2 |
| `xml_sax_xmlreader` / `pyperf` / `genshi_core` / `constants` | 2 each |
| `CodecInfo`, `MULTILINE`, `digits`, `os`, `python_implementation`, `Mapping`, `_utils`, `urllib_request`, `setuptools`, `os_path`, `docutils`, `colorsys`, `argparse` | 1 each |

**~40 of 58 files stop at a missing module.** `six` alone is 15 and is already
measured as a pure shim job. This is the fourth time this ticket has measured
that the ladder is gated by class-4 stdlib surface rather than by the NilPy
language, and the first time it has been measured with `-Fu` and against a pin.

The `class Filter cannot inherit from itself` row (3 files) is **not a
regression** — identical on the pinned compiler — and **not a corpus blocker**:
those files are imported in real use, and the module path works. See
[[bug-n-class-x-inherits-mod-x-is-refused-in-the-main-program]], including the
method caveat that standalone-compiling every file overstates the walls.

### Recommendation

Further Track N work on this ticket has **low yield** until the shims exist. The
next unit of progress is `mimic_six` (15 files), then `codecs.CodecInfo`
(webencodings' last wall), then `warnings`. All Track B.

## PARKED 2026-08-17 — not blocked on Track N, and the deliverable is still unwired

Moved out of `working/` because this session halted with it incomplete rather
than finished. **The Makefile corpus targets — this ticket's actual deliverable —
are still not wired.** Three frontend fixes landed and none of them was that.

Why parked rather than pushed further: wiring `webencodings` today would assert
`codecs.CodecInfo`, a Track B `mimic_codecs` gap, not a corpus result — a target
that tests another lane's hole is worse than no target, because it goes red for a
reason its own lane cannot fix. The A/B scan above is the evidence: ~40 of 58
files stop at a missing module, and Track N is not the lever.

Critical path is now `decide-how-python-shaped-shims-should-be-shipped`
(raised to 70 by the coordinator on these numbers, with the user). Nothing here
is buildable until that is answered — which is why this is parked on a decision
rather than on work.

**Resume condition:** the shim question is answered and `mimic_six` exists (15 of
58 files). Then re-run the A/B scan in this file — with `-Fu`, against a pin, and
naming the sha — before choosing the next rung. Do not read the next step out of
the prose above; every scan in this file has been superseded by the next one.
