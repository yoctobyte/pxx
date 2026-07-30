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

## Forks for Track U (escalate, do not guess)

- `decide-pil-mimic-vs-cfront-codecs` — for a class-3 dependency, do we (a)
  mimic the module surface in `lib/`, (b) compile the underlying C library with
  cfront and write our own binding, or (c) declare the app's feature optional?
  Pillow is the first instance and sets the precedent.
- `decide-cpython-c-api-support` — is implementing (a subset of) the CPython
  C-API ever on the table? Answering "no" permanently is a legitimate and
  probably correct answer; it just needs to be recorded, because it decides the
  fate of every class-3 dependency.
- where do compiled third-party libraries LIVE? A vendored corpus dir vs
  compiling from the user's site-packages in place. Affects how the frontend
  resolves `import html5lib`.

## Children (file as they start)

- [[feature-nilpy-future-import-noop]]
- [[feature-nilpy-dataclasses]]
- [[feature-nilpy-corpus-html5lib]]
- [[feature-nilpy-corpus-neuzelaar]]
