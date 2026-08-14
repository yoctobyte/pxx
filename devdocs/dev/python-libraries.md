# Third-party Python libraries as pxx targets

How pxx consumes a library the application `import`s. Written 2026-07-31 after
the Track U decision on the CPython C-API; the tickets that execute it are
[`feature-nilpy-thirdparty-libraries-as-targets`](../progress/backlog/feature-nilpy-thirdparty-libraries-as-targets.md)
and [`feature-nilpy-cpyext-c-api-from-source`](../progress/backlog/feature-nilpy-cpyext-c-api-from-source.md).

The goal is **compiling Python libraries**, not any particular application. An
app (songformatter, neuzelaar) is a forcing target that tells us which library
to do next — never a goal in itself.

## 1. Classify the dependency first

Four kinds, not two. They cost wildly different amounts:

| class | what it is | how to spot it |
| --- | --- | --- |
| **1 pure Python** | ordinary `.py`, stdlib only | no `.so` in the installed package; wheel tag `py3-none-any` |
| **2 ctypes / cffi** | pure Python that `dlopen`s an ordinary C library — no `Python.h` anywhere | no `.so` of its own, but imports `ctypes`/`cffi` |
| **3 CPython C-API extension** | C/C++/Rust compiled against `Python.h`, calling `PyObject_*`. Cython, PyO3, pybind11 all land here | a `.so` in the package; wheel tag `cp312-manylinux_x86_64` |
| **4 stdlib-C edge** | no bindings of its own, but leans on `re`, `zlib`, `json`, `hashlib`, `socket`, `ssl` | plain imports |

Triage without reading anything:

```sh
find <site-packages>/<pkg> -name '*.so' | head    # empty => class 1 or 2
grep -rlE '^[[:space:]]*(import|from)[[:space:]]+(ctypes|cffi)\b' <site-packages>/<pkg>
#   ^ anchored to an IMPORT on purpose: a plain `grep -rl 'ctypes\|cffi'`
#     matches the substring in `doctypeClass`, which is ordinary HTML-parser
#     vocabulary -- it misclassifies html5lib (class 1) as class 2. Measured
#     2026-08-14 on the neuzelaar venv; the corrected form reproduces every
#     verdict in the table below.
```

**A wheel is a distribution format, not a build strategy.** It ships what
someone already built so the installing machine needs no compiler; it never
removes the native code. Its only value to us is triage: the tag names the
class for free.

## 2. The strategy ladder — mimicking is the LAST resort

| situation | strategy | why |
| --- | --- | --- |
| class 1 pure Python | **compile their real source, unchanged** | it is just more source. Tracks upstream for free |
| class 2 ctypes/cffi | **cfront the C library, bind natively** | plays to what pxx already is |
| class 3, sane build | **cpyext — compile their C source against our own `Python.h`** | our ABI, static binary, generalises to everything Cython/PyO3/pybind11 emit |
| class 3, insane build (CUDA, Fortran, giant C++, cmake maze) | **bind the NATIVE library directly, under a mimic surface** | torch's Python layer is a thin wrapper over a C++ library; going through the bindings to reach it is the detour |
| no native library to borrow (reportlab) | **write our own** | permanent maintenance, so only when nothing can be borrowed |

**Never load a prebuilt `.so`.** Decided, with reasons, in the cpyext ticket:
the artifact is pinned to one CPython minor ABI on one architecture, its
machine code has `Py_INCREF`, struct offsets and the GC header already inlined
(so it demands CPython's exact *binary object model*, not merely its API), and
it yields nothing on any cross target. Shipping `.so`s beside the app gives
back exactly what static linking bought.

**Why mimicking is the last resort.** Every mimic is a private fork of someone
else's API. It drifts, it is incomplete in ways only found at run time, and it
is ours forever. Compiled real source has none of that: upstream fixes a bug,
we recompile. Existing mimics (`lib/pcl/mimic_reportlab_*`) exist because
reportlab had no borrowable engine, not because mimicking is the pattern.

Two rules that DO carry over from the reportlab work:

- **Implement only the surface the compiled code touches.** `mimic_reportlab_pdfgen`
  is not reportlab; it is the ~15% songformatter calls.
- **Look, don't copy.** We never port their implementation, but we keep the
  real library installed and DIFF against it. Their behaviour is the spec.

## 3. Per-library choices need a recipe

The strategy is a per-library decision, and the same library can be revisited
(mimic today because cpyext is young, compiled from source later). That choice,
and everything needed to act on it, belongs in a **recipe** checked into the
repo — one per library, the way a distro packages software.

Resolution today is name-based (`compiler/pyparser.inc`, `PyConsumeDottedModule`):
`import reportlab.lib.colors` looks for the unit `reportlab_lib_colors`, then
falls back to `mimic_reportlab_lib_colors`. A recipe does not replace that; it
records *how the unit that satisfies the import gets built*, and lets the
build/test tooling act without a human remembering.

Proposed shape (ini, one file per library, e.g. `lib/pyrecipes/html5lib.ini`):

```ini
[library]
name     = html5lib
version  = 1.1                  ; PINNED — no resolver, no environment markers
class    = 1                    ; 1 pure | 2 ctypes | 3 capi | 4 stdlib-edge
strategy = compile-source       ; compile-source | cpyext | bind-native | mimic | own
status   = wip                  ; wip | green | blocked | wont-do
reason   =                      ; required when strategy is mimic/own/wont-do

[source]
; where the .py we compile comes from. site-packages is a perfectly good
; source tree; vendoring is for when we must pin or patch.
from     = site-packages        ; site-packages | vendored
path     = vendor/html5lib-1.1

[oracle]
; how to run the REAL library under CPython for differential testing
venv     = ~/neuzelaar2/.venv
command  = python -m pytest html5lib/tests

[surface]
; mimic/own only: what we actually implement, so incompleteness is declared
; rather than discovered at run time
implements = parse, parseFragment, serialize
```

For `strategy = cpyext` the recipe additionally carries what `setup.py` would
have said, because we do not run `setup.py`:

```ini
[build]
sources  = src/_imaging.c src/decode.c src/encode.c
defines  = HAVE_LIBJPEG HAVE_LIBZ
includes = src/libImaging
links    = libjpeg libz            ; themselves cfront corpus targets
```

Curated recipes, not build-system interpretation, is what keeps this tractable
— and it makes the supported set **explicit and testable** instead of
aspirational. (Running `setup.py` under NilPy itself is a real and amusing
option; it is not the first move.)

## 4. Installing things is fair game

Full Python support means the *build machine* keeps a normal Python
environment. That is fine, and it is worth being precise about which side of
the line each use falls on:

| we install a library for… | ok? |
| --- | --- |
| its **source**, as compiler input (site-packages is a fine source tree) | yes |
| its use as the **oracle** in differential tests | yes — this is how we verify |
| its `.so`, loaded by the produced program | **no** — that is the rejected wheel path |

So: `pip install` at development time, **nothing at run time**. The shipped
artifact stays a single static binary — no interpreter, no `.so`, no
site-packages — and cross-compiles to targets where no wheel was ever
published. That is the whole point, and it is the property to protect when a
shortcut is tempting.

## 5. Won't-do tier, declared up front

Recorded so it is not re-argued monthly: **CUDA toolchains, Fortran
(scipy/BLAS/LAPACK), and million-line template C++ (torch, tensorflow)** are
not compiled from source. If an application needs them, the answer is the
native-binding row of the ladder (bind libtorch / the CUDA driver API under our
own surface), or the library is out of scope for that application.

Selection policy for what we DO take on: **by build simplicity, not
popularity.** Single-file, no-dependency C first.

## 6. Where the work shows up

- class 1 libraries → NilPy corpora, each gated on its own upstream test suite
  (a library that compiles and passes its own tests is a permanent asset)
- the C source of class 2/3 → **cfront** corpus stressors; expect the first
  walls to be ordinary C-frontend gaps (macros, `#include` chains, unions,
  varargs), not API design
- the stdlib surface (class 4) → `lib/rtl`, and it is the same list for every
  app, so it pays forward

## 7. Measuring where you actually are — the census

Everything above classifies *dependencies*. This section is about measuring the
**application**, and it exists because the campaign's written schedule was wrong
in a way nobody could see.

### The lesson, first

On 2026-08-14 the plan in `feature-nilpy-thirdparty-libraries-as-targets` named
two next steps: make `from __future__ import annotations` a no-op, then
`@dataclass`. **Both were already working.** All nine `__future__` feature names
compile and match CPython; `@dataclass` produces `Point(x=1, y=2)`, identical to
CPython. The document had been written from a census taken six weeks earlier and
had rotted silently — following it would have meant implementing solved problems.

So: **a per-construct schedule does not belong in a document.** The compiler moves
daily; a census is a *command*, and "what is next" is regenerated from it, never
remembered. The classification rule in §1 did not rot, because it describes
Python packaging rather than pxx. Write down rules; regenerate numbers.

### Bucket by KIND, not by count

The raw failure histogram is misleading — it lists symptoms, and one mechanism
can produce a hundred of them. Bucketing the same 150 failures by kind is what
schedules work. Measured on neuzelaar, 168 git-tracked files, 26,408 lines,
**18 compiling (11%)**:

| failure kind | files | what it means |
| --- | --- | --- |
| **intra-project imports** | **89** | ONE defect, not 89 |
| stdlib imports (`enum`, `argparse`, `datetime`, `contextlib`, `threading`, `importlib`) | 28 | class 4 — `lib/` work, reusable across every app |
| third-party imports (`pytest`, `yaml`, …) | 19 | mostly test-only; not on the app's path |
| language / frontend gaps | 14 | actual frontend work |

The old plan called `@dataclass` "the one construct that gates most of the
corpus". Measured: **5 files**. The gate is intra-project imports at 89 — a
dotted import resolves only to a hand-written `mimic_*` shim and never looks for
the source file on disk (`feature-nilpy-dotted-imports-resolve-to-source-files`).

**The language-gap column is a LOWER BOUND.** A file that fails on its first
import is never compiled, so its remaining constructs were never exercised.
Expect that column to grow as imports start resolving. It is an argument for
fixing imports first, not a reason to distrust the number.

### Two traps that each produced a confident wrong answer

Both were caught only by noticing the output looked odd, which is not a method.
Check for them explicitly.

1. **Census the GIT-TRACKED files.** An `os.walk` of a project directory picks up
   vendored trees. In neuzelaar that is a Web Platform Tests corpus — **549**
   files of third-party fixtures — producing a clean-looking histogram of
   entirely the wrong population (`wptserve_utils`, `sec-ch-ua.py`, `beacon.py`).
   `git ls-files '*.py'` is what defines the corpus; it returns exactly the 168
   files / 26.4k lines the ticket claims.
2. **Write results incrementally.** A serial run that only summarises at the end
   dies on a wall-clock cap with *nothing* to show. Append one JSON line per file
   as it lands, and a killed run is still a usable partial census.

Also: run it in parallel with a short per-file timeout. 168 files with a 60s
per-file allowance does not fit in a 15-minute cap; 8 workers and a 20s timeout
finishes comfortably.

### The recipe

Kept here rather than as a checked-in tool on purpose — it is ~40 lines and the
corpus path changes per app. If it earns a second regular user, promote it to
`tools/`.

```python
# for each git-tracked .py: compile with pxx, keep the FIRST "error:" line,
# normalise it (strip the file:line prefix, replace quoted identifiers with 'X')
# so the same defect from different files collapses into one bucket.
files = subprocess.run(["git","-C",ROOT,"ls-files","*.py"],
                       capture_output=True, text=True, check=True).stdout.split()
# ... ProcessPoolExecutor(max_workers=8); subprocess.run([pxx, f, tmp], timeout=20)
# ... append json.dumps({"f":f,"ok":rc==0,"err":norm(line)}) per result, flush
```

Then bucket by kind: an error matching `no unit named <u>` is an *import* failure
and splits three ways by `<u>` — the project's own top-level package name,
a stdlib module name, or anything else. Everything that is not an import failure
is a language gap.

### The standing caveat, and what was done about it

The driving corpus lives **outside this repo**. No tier runs it, no tstate report
regresses it, and every number here is a claim only the machine holding that
checkout can verify. That is fine for exploration and not fine for gating: a
census finding must be re-derived as an ordinary `.npy` test under `test/` before
anything depends on it.

**So the finding was vendored, not the corpus** (user, 2026-08-14). The census's
dominant result — dotted imports never resolving to a source file — now has an
in-repo fixture, `test/nilpy_units/pkgcorpus/` plus
`test/test_nilpy_package_imports.npy`, which reproduces the diagnostic on any
machine and is the gate for
`feature-nilpy-dotted-imports-resolve-to-source-files`.

Two things worth copying when the next finding gets vendored:

- **Shape the fixture from what the corpus MEASURABLY does.** neuzelaar uses
  absolute dotted imports exclusively and has **zero** relative imports across
  168 files, so the fixture has none either. Relative imports are what everyone
  assumes such a fixture needs; including them would have gated work nothing
  needs yet.
- **Do not wire a known-failing fixture into a gated target.** It goes red the
  day it lands, for a known cause, which is the flakiness-shaped failure mode
  Track T removes. Wire it in with the fix.

What did NOT need vendoring: `__future__` and `@dataclass` already had thorough
tests (`test_nilpy_future_import.npy`, and a dozen `test_nilpy_dataclass_*`).
They were never untested — the ticket was simply never updated when they landed,
which is the same "regenerate, don't remember" lesson from the top of this
section wearing different clothes.
