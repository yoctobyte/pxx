---
track: N
prio: 60
type: feature
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
grep -rl 'ctypes\|cffi' <site-packages>/<pkg>      # non-empty => class 2
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

## First walls, already probed

- `from __future__ import annotations` — **86 files**, and it is the very first
  error (`no unit named __future__`). In NilPy this is a no-op the frontend
  should swallow. Small Track N fix, do it first.
- construct census over the 168 files: 60 `@dataclass`, 70 f-strings, 22
  lambda, 11 `Enum`, 11 generators (`yield`), 9 `@property`, 8 `super()`,
  6 `@classmethod`, 4 threading, 3 `match`, 2 walrus, 1 `Protocol`,
  1 `__slots__`. No `async def`, no `@abstractmethod`.
  **`@dataclass` at 60 files decides the schedule.**

## Plan

1. `__future__` import is a no-op (Track N, small).
2. `@dataclass` — the one construct that gates most of the corpus.
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
