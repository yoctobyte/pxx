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
