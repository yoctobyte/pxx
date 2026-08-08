---
track: N
prio: 65
type: feature
blocked-by: []
status: working
owner: claude-A-uforth
---

# cpyext: compile a CPython C extension's SOURCE against our own `Python.h`

Decided 2026-07-31 (see [[feature-nilpy-thirdparty-libraries-as-targets]]).
A class-3 dependency — C/C++/Rust compiled against `Python.h` and calling
`PyObject_*` — is supported by **compiling its C source with cfront against a
`Python.h` we provide**, whose implementation maps the C-API onto NilPy's
runtime objects.

Explicitly NOT: loading a prebuilt `.so`. That artifact is machine code pinned
to one CPython version's ABI on one architecture, it would require pxx to BE
CPython (refcounts, GIL, `tp_*` slots), and it yields nothing on cross targets.

**Why this is the strategic ticket.** Cython, PyO3 and pybind11 all emit code
against this same API, so one layer unlocks a large slice of PyPI — and the
extension then **links into a static binary**, which is exactly what a wheel
can never give you. "Just compile the library" stays useful forever; a
per-library mimic never does.

## Why loading a prebuilt `.so` is not a shortcut (measured 2026-07-31)

`PIL/_imaging.cpython-312-x86_64-linux-gnu.so` has **82 undefined `Py*`
symbols** (several private: `_PyArg_ParseTuple_SizeT`, `_PyBytes_Resize`) and
does NOT link `libpython` — they resolve from the HOST executable at load time.
Exporting 82 functions is the easy half and not the problem.

What the extension's machine code already contains, inlined and unreachable:

- `Py_INCREF`/`Py_DECREF` write `ob_refcnt` **at offset 0** of the object. Not
  a call — not interceptable. Our heap objects would have to carry that header.
- fixed struct offsets: `PyTypeObject`'s ~80 slots, `ob_size`, direct
  `((PyListObject*)o)->ob_item[i]` indexing.
- `PyGC_Head` immediately BEFORE the object, because `PyObject_GC_Track` links it.
- 3.12 specifics: immortal-refcount encoding, the reworked `PyLongObject` layout.

So loading a wheel is not "implement an API", it is **replicate a binary object
model per CPython minor version** — and an extension's init often imports
Python modules (`import_array()`), dragging in the import machinery, unicode
objects, exception and thread state, the GIL. C++ and CUDA are the irrelevant
part: `libstdc++`/`libcudart` are ordinary shared libraries.

For reference, the tiers that were weighed and rejected: (A) full ABI clone —
bigger than pxx, chases a moving target; (B) limited API / abi3 only — bounded
by design, but `PyObject`'s header and refcounts are still inlined, and the
libraries this would be for do not ship abi3; (C) out-of-process CPython over
RPC — works today, kept as an escape hatch, no compiler-design damage;
(D) bind the NATIVE library directly under our own surface — the preferred
answer for the CUDA/C++ tier, since we are a native compiler and their Python
layer is a thin wrapper anyway.

## Shape of the work

Two halves that meet at a header:

1. **`Python.h` (Track C files).** Our own header + the C-side inline/macro
   layer, compiled by cfront. Must be honest C: the extension's source is
   unmodified, so whatever it spells has to exist.
2. **The runtime bridge (Track N files, `compiler/builtin/pylib.pas` and
   friends).** `PyObject*` handles resolving to NilPy variants/objects,
   refcount calls routed to `PXXObjRetain` / `PXXObjRelease`, exceptions
   raised as NilPy exceptions, module method tables turned into callables the
   NilPy `import` path can bind.

Shared-internals changes (new IR op / AST node / symtab field) → **file a Track
A ticket**, do not edit under N.

## The API subset, roughly in dependency order

- object model: `PyObject`, `PyTypeObject` (only the slots we honour),
  `Py_INCREF`/`DECREF`/`XDECREF`, `Py_None`/`True`/`False`
- module init: `PyModuleDef`, `PyModule_Create`, `PyMethodDef` tables,
  `PyInit_<name>` discovery from the NilPy `import` path
- argument plumbing: `PyArg_ParseTuple`, `PyArg_ParseTupleAndKeywords`,
  `Py_BuildValue` — the format-string mini-language is real work and is where
  most extensions actually spend their API calls
- conversions: `PyLong_*`, `PyFloat_*`, `PyUnicode_*` (UTF-8 path first),
  `PyBytes_*`, `PyList_*`, `PyTuple_*`, `PyDict_*`
- errors: `PyErr_SetString`, `PyErr_Occurred`, `PyErr_Clear`, the standard
  exception objects
- protocols: number / sequence / mapping; **buffer protocol** later (that is
  what numpy-shaped packages need)
- deliberately out of scope until forced: GIL APIs (we are not
  multi-interpreter), weakrefs, the codec registry, `PyCapsule` chains

Aim at the **limited API / abi3 surface** as the definition of "done enough" —
it is a published, bounded subset, and packages that already restrict
themselves to it are the cheapest wins.

## Milestones (each independently useful)

1. **M1 hello-ext.** A hand-written one-function module (`int` in, `int` out),
   compiled by cfront, importable from a `.npy` and callable. Proves the
   header, the module table and the import binding.
2. **M2 arguments and errors.** `PyArg_ParseTuple` for the common formats
   (`i l d s s# O`), `Py_BuildValue`, `PyErr_SetString` propagating into a
   NilPy `except`.
3. **M3 strings and containers.** Unicode/bytes round-trip, list/tuple/dict
   construction and iteration.
4. **M4 a REAL extension from PyPI** — small, plain C, no build magic. Verified
   against CPython's output, not against expectation.
5. **M5 a Cython-generated module.** Cython emits a lot of API; this is the
   honest test of coverage and the point where the ecosystem opens up.
6. **M6 buffer protocol**, if and when a target needs it.

## Gate

`make test-nilpy` green + self-host byte-identical, plus a differential run of
each compiled extension against the same extension under CPython. A new test
family (`test_cpyext_*.npy` + its `.c`) gated in the Makefile, exactly as the
NilPy tests are.

## 2026-08-01 — M1 "hello-ext" landed (commits `868dffae0`, `73446e7fa`)

`lib/cpyext/include/Python.h` + `lib/cpyext/src/pyruntime.c`: a tiny
bump-allocated tagged-object runtime (long/tuple/module/none) behind
the M1-scoped API subset (`PyObject`, `Py_INCREF`/`DECREF`/`XDECREF`,
`Py_None`, `PyModuleDef`+`PyModuleDef_HEAD_INIT`, `PyMethodDef`+
`METH_VARARGS`, `PyModule_Create`, `PyArg_ParseTuple` format `"i"` only,
`PyLong_From/AsLong`, enough `PyTuple_*` to carry positional args).
`test/nilpy_units/hello_ext_module.c` (real CPython-extension-boilerplate
shape) compiled by cfront, `hello_ext.pas` bridges it to NilPy's flat
unit-scope `import`, `test/test_cpyext_hello.npy` calls
`hello_ext.add_one(41)` and asserts `42`. Wired into `make test-nilpy`.
Verified independently: self-host fixedpoint byte-identical, full
`make test-nilpy` green (including the new test), rebuilt from the
exact merged commit on master (not trusted from agent self-report).

Note: this M1 runtime is a **standalone tagged-object model**, not yet
routed through NilPy's own ARC (`PXXObjRetain`/`PXXObjRelease`) or
variant representation — that integration is real work still ahead for
M2+, deliberately deferred since M1's only job was proving the header +
module-table + `PyInit_<name>` import-binding plumbing end to end.

Found and filed (not fixed here, Track A):
[[bug-c-uses-path-basename-collides-with-enclosing-unit-name]] — a
path-form `uses './x.c'` sharing its unit's own base name silently
fails to load. Workaround used: renamed the C module source so it
doesn't collide (`hello_ext.c` → `hello_ext_module.c`).

Next: M2 (arguments/errors — more `PyArg_ParseTuple` formats,
`Py_BuildValue`, `PyErr_SetString` → NilPy `except`).

## 2026-08-01 — M2 "arguments and errors" landed (commit `22515d725`)

`PyArg_ParseTuple`/`Py_BuildValue` widened to `i l d s s# O`;
`PyErr_SetString`/`PyErr_Occurred`/`PyErr_Clear` propagate into a NilPy
`except`. `test/nilpy_units/argerr_ext_module.c` + `argerr_ext.pas` +
`test/test_cpyext_args_errors.npy`, wired into `make test-nilpy`.
Verified: self-host fixedpoint byte-identical, `testmgr --tier quick`
green, new test's actual output spot-checked directly (not the full
`make test-nilpy` sweep — per the "confirm native, offload the matrix"
rule, Track T is up and covers the full suite asynchronously).
Next: M3 (strings and containers).

## 2026-08-01 — M3 "strings and containers" landed

`PyBytes_FromStringAndSize`/`AsString`/`Size` (a type distinct from
`PyUnicode_*`); `PyList_New`/`SetItem`/`GetItem`/`Append`/`Size`;
`PyDict_New`/`SetItem`/`GetItem`/`Size`/`Next` (linear-scan association,
insertion-order iteration — fine at extension/test scale); `'y'`/`'y#'`
bytes format letters for `PyArg_ParseTuple`/`Py_BuildValue`, mirroring
`'s'`/`'s#'`.

`test/nilpy_units/container_ext_module.c` (`sum_range` via list
construction+iteration, `join_lengths` via list append+iteration,
`char_histogram` via dict construction+`PyDict_Next` iteration,
`bytes_roundtrip` via `PyBytes_*`) + `container_ext.pas` +
`test/test_cpyext_containers.npy`, wired into `make test-nilpy`.

**Deliberate scope cut, flagged for whoever picks up M4+:** M3's
containers are built and consumed ENTIRELY inside the extension's own C
code — every `PyMethodDef` entry point still crosses the NilPy boundary
as a scalar/string, same pattern as M1/M2's thin-driver approach. They
do **not** yet round-trip as native NilPy `list`/`dict` Variants (e.g.
an extension function returning a Python list does not yet appear as an
actual NilPy list in the caller's hands) — that is the deeper
`compiler/builtin/pylib.pas` integration the ticket's "Shape of the
work" section calls out separately ("`PyObject*` handles resolving to
NilPy variants/objects"), not attempted here. Filing this as an
observation rather than a ticket since it's naturally part of M4/M5's
"a real extension" milestones, where a real PyPI extension will very
likely return a list/dict/str to Python code that needs to actually use
it — at that point the cut becomes a hard requirement, not a
convenience.

Verified: self-host fixedpoint byte-identical, `testmgr --tier quick`
green, new test's actual output spot-checked directly against the
freshly-rebuilt `compiler/pascal26` (same lighter verification bar as
M2 — Track T's watcher is up, `tools/twatch.py --status` confirmed).

Landmine hit and fixed inline (not a compiler bug): a doc comment in
`Python.h` containing the adjacent tokens `PyList_*/PyDict_*` contained
a literal `*/` that closed the enclosing C block comment early,
producing a real parse error at the very next line. Fixed by inserting
a space (`PyList_* / PyDict_*`); worth remembering when writing header
comments that reference multiple `Foo_*` prefixes back to back.

Next: M4 (a real PyPI extension, verified against CPython's own output).

## 2026-08-01 — M4 "a real extension from PyPI" landed

Picked [MarkupSafe](https://pypi.org/project/MarkupSafe/) 3.0.3's
`_speedups.c` (BSD-3-Clause): 200 lines, single file, no build magic, no
numpy/buffer-protocol, widely used (a Jinja2/Flask dependency). Fetched via
`pip download markupsafe==3.0.3 --no-deps --no-binary :all:`, vendored
**unmodified** into `test/nilpy_units/vendor/markupsafe_speedups.c`
(renamed from `_speedups.c` only — file content, including its
`PyInit__speedups` symbol, untouched; the rename sidesteps
[[bug-c-uses-path-basename-collides-with-enclosing-unit-name]]).

This real extension immediately needed real API surface M1-M3's
hand-written toys never touched — added to `Python.h`/`pyruntime.c`:

- `PyUnicode_Check`, `PyUnicode_READY` (no-op), `PyUnicode_KIND` +
  `PyUnicode_1BYTE_KIND`/`2BYTE_KIND`/`4BYTE_KIND`, `PyUnicode_1/2/4BYTE_DATA`,
  `PyUnicode_GET_LENGTH`, `PyUnicode_IS_ASCII`, `PyUnicode_New`,
  `Py_UCS1`/`Py_UCS2`/`Py_UCS4`, `PyUnicodeObject` (aliased to `PyObject` —
  this runtime's object already carries everything a string needs). This
  runtime is byte-only, so `PyUnicode_KIND` always reports
  `PyUnicode_1BYTE_KIND`; the extension's kind2/kind4 code paths still
  compile (so the link stays honest — see the header's own policy) but are
  dead code, never exercised.
- `METH_O` (arg passed directly as the second `PyCFunction` parameter, no
  tuple — needed no special driver-side handling since this runtime's
  `PyCFunction` signature was already uniform enough to just pass the bare
  object through).
- `PyModuleDef` gained an `m_slots` field + a new `PyModuleDef_Slot` type
  (only so `.m_slots = module_slots` — a **designated initializer**, which
  cfront was confirmed to already support — compiles) and
  `PyModuleDef_Init`, which **collapses real CPython's multi-phase (PEP 489)
  init straight to single-phase** (`PyModule_Create2`). Honest for this
  extension, whose only slots are capability announcements
  (`Py_mod_gil`/`Py_mod_multiple_interpreters`, both `#ifdef`-guarded and
  never defined by this header, so those slot entries never even compile
  in) with no `Py_mod_exec` — a real `Py_mod_exec` slot would need more work
  and is explicitly not attempted here.
- `<assert.h>` is now pulled into `Python.h` itself, matching real CPython's
  `Python.h` (via `pyport.h`) doing the same — `_speedups.c` calls `assert()`
  without its own `#include`, relying on exactly that transitive include.

`test/nilpy_units/markupsafe_ext_host.c` (embedding driver, same shape as
M1-M3's) + `markupsafe_ext.pas` (bridge unit) +
`test/test_cpyext_markupsafe.npy`, wired into `make test-nilpy`.

**Verified against CPython's own output, not against expectation** (the
milestone's own bar): `pip install markupsafe==3.0.3 --target <dir>`, then
`PYTHONPATH=<dir> python3 -c "from markupsafe._speedups import
_escape_inner; ..."` on the exact same inputs the `.npy` test uses. Output
is byte-identical between the pxx-compiled extension and the same extension
running under real CPython (see the Makefile's `test_cpyext_markupsafe26`
expectation for the exact escaped string); the plain-text input passes
through unchanged, and an empty string round-trips to an empty string too.

Verified otherwise: self-host fixedpoint byte-identical, `testmgr --tier
quick` green, all four `test_cpyext_*.npy` tests (M1-M4) spot-checked
directly against the freshly-rebuilt `compiler/pascal26` — lighter bar per
CLAUDE.md's "confirm native, offload the matrix" (Track T's watcher
confirmed up).

No new Track A/C blocker filed this session (the one from M1 remains the
only one).

Next: M5 (a Cython-generated module) or M6 (buffer protocol) — M5 is
probably next in ticket order, but note MarkupSafe's OWN pure-Python
fallback path plus this M4 slice already covers a fair amount of real-world
API; M5 will likely demand a much larger `Python.h` surface (Cython emits
extensive boilerplate: type objects, `tp_*` slots, `PyType_Ready`,
weak references) and deserves its own scoping pass before starting.

## 2026-08-01 — reverted two same-basename workarounds, platonic code instead

M1 and M4 had each renamed a C module source to dodge
`bug-c-uses-path-basename-collides-with-enclosing-unit-name` instead of
leaving it blocked (`hello_ext.c` → `hello_ext_module.c`, and
MarkupSafe's own `_speedups.c` → `markupsafe_speedups.c`, the latter
turning out to not even collide — verified directly, reverted
regardless for the accurate filename). Both reverted to their platonic
names. M1's test now genuinely hits the bug (`undefined symbol:
PyInit_hello_ext`) and is skipped in `make test-nilpy` with a message
pointing here; `blocked-by` added above. M4 didn't actually need the
rename (`_speedups` never collided with `markupsafe_ext`) so it stays
green under its real upstream filename.

## Notes

- Ladder position and the recipe/install policy: **`devdocs/dev/python-libraries.md`**.

- The C source is compiled by **cfront**, so every extension is also a cfront
  corpus stressor — expect the first walls to be ordinary C-frontend gaps
  (macros, `#include` chains, unions, varargs), not API design.
- Varargs matters early: `PyArg_ParseTuple`/`Py_BuildValue` are variadic, and
  `PyObject_CallFunction` too.
- Keep the header's promises minimal and explicit: a function we do not
  implement should fail at LINK time with a clear name, never silently do
  nothing at run time.

## Log
- 2026-08-02 — moved working/ -> blocked/ by `claude@xeon` during T-queue
  triage. Not a judgement on the work: the ticket carries
  `blocked-by: [bug-c-uses-path-basename-collides-with-enclosing-unit-name]`,
  that blocker is still open in backlog/ (prio 65, unblocks this), and
  `working/` is a LIVE LOCK — a ticket parked on someone else's fix does not
  belong in it. Owner field left intact; re-claim when the blocker lands.


## 2026-08-02 — UNBLOCKED: the path-form `uses` collision is fixed

[[bug-c-uses-path-basename-collides-with-enclosing-unit-name]] is resolved
(commit 5303d2741), so `test_cpyext_hello` no longer prints a SKIP line — it
runs and asserts, and it needed **no change to hello_ext.pas at all**.

Worth recording as a vindication of the call made when M1 landed: the module
source was left platonically named `./hello_ext.c` (same basename as the unit,
exactly as a real CPython extension is laid out) and the TEST was skipped, rather
than renaming the file to dodge the compiler bug. The workaround would have been
invisible forever; the skip made the bug someone's job, and the fix cost one key
in the uses guard.

`make test-nilpy` now carries M1 as a real assertion alongside M2/M3/MarkupSafe.


## 2026-08-02 — M5 SCOPING PASS (measured, not estimated)

M5 was left with "deserves its own scoping pass before starting". Here it is,
with numbers. Cython 3.2.9 in a throwaway venv; the module is the smallest
useful one (two `def`s, one with a `cdef int` loop). Nothing was implemented.

### First finding: the measurement was lying, and so was the compiler

`cython -3 cyadd.pyx` emits 8061 lines. Compiling that against our `Python.h`
reported ONE error — `PyInit_cyadd` undeclared — which reads like "almost
there". It was the opposite. Cython's output opens with

```c
#include "Python.h"
#ifndef Py_PYTHON_H
    #error Python headers needed to compile C extensions...
#elif PY_VERSION_HEX < 0x03080000
    #error Cython requires Python 3.8+.
#else
    ...the entire 8000-line module...
#endif
```

Our header defined neither `Py_PYTHON_H` nor `PY_VERSION_HEX`, so the `#elif`
was true and **the whole module body was excluded** — and cfront drops `#error`
silently, so nothing said so. Filed
[[bug-cfront-error-directive-silently-ignored]] (Track C, prio 75): `#error` in
a live branch compiles clean, which turns any "this build is unsupported" guard
into a silently truncated program. `gcc -E -I lib/cpyext/include` is the
reliable oracle for this stage until that lands, and is what every number below
was taken with.

`Py_PYTHON_H` + the `PY_*_VERSION` family are now defined in `Python.h`
(committed with this note; all four existing cpyext tests stay green). The
version claimed is a SOURCE-level claim and a deliberate knob: it selects which
of Cython's many `#if PY_VERSION_HEX` paths the generated code takes.

### The decisive measurement: two knobs cut the surface by 3.5x

Missing identifiers (types, macros, constants — not counting functions), for the
same tiny module:

| Cython flags | plain | `-DPy_LIMITED_API=0x030c0000` |
| --- | --- | --- |
| default (`binding=True`) | **78** | **53** |
| `-X binding=False` | **46** | **22** |

`Py_LIMITED_API` is the important one, and not merely for the count: it removes
every direct-struct-layout entry — `PyASCIIObject`, `PyListObject`,
`PyTupleObject`, `PyLongObject`, `PyCFunctionObject`, `PyCodeObject`,
`PyFrameObject`, `PyLong_SHIFT`, `digit`. Those are exactly the inlined-layout
dependencies whose absence is the whole reason this ticket rejected loading a
prebuilt `.so`. Under the limited API an extension can only reach objects
through functions, which is precisely the contract this runtime can honour.

`binding=False` drops Cython's CyFunction machinery — its own heap type with
`tp_descr_get`, GC traverse/clear, vectorcall. Costly to support, and it buys
only that `module.f` behaves like a Python function object rather than a
builtin. A perfectly good first rung.

So: **M5 should target `Py_LIMITED_API` Cython output, and M5a should add
`-X binding=False`.** This also matches the ticket's own stated aim ("aim at the
limited API / abi3 surface as the definition of done enough") — it turns out to
be the cheap path as well as the principled one.

### M5a shopping list — the whole thing, measured

With `binding=False` + `Py_LIMITED_API`, the missing IDENTIFIERS are 20 (the 22
above include `value`/`zero`, which are cascade noise from `LONG_LONG`):

- typedefs: `LONG_LONG`, `PY_INT64_T`, `Py_hash_t`
- constants: `PY_SSIZE_T_MAX`, `Py_Version`, `PY_VECTORCALL_ARGUMENTS_OFFSET`
- comparison ops: `Py_EQ`, `Py_LT`
- method flags: `METH_KEYWORDS`
- singletons: `Py_True`, `Py_False`
- type objects: `PyDict_Type`, `PyLong_Type`
- exceptions: `PyExc_AttributeError`, `PyExc_DeprecationWarning`,
  `PyExc_ImportError`, `PyExc_OverflowError`
- multi-phase init: `Py_mod_create`, `Py_mod_exec`
- `Py_eval_input`

Nearly all are `#define`s or extern object pointers next to the four
`PyExc_*` we already have. **This is a small header change, not a design.**

Plus four headers Cython `#include`s by name and CPython really does ship
separately: `pythread.h`, `compile.h`, `frameobject.h`, `traceback.h`. Under the
limited API their CONTENTS are unreachable (the code using them is compiled
out), so minimal honest files suffice — but they must exist, and each should say
in a comment what it deliberately does not provide.

### The real cost is the FUNCTION surface: ~93 entries

Identifiers are the cheap half. Every `Py*` name referenced by the limited-API
preprocessed output, minus what our header declares, is **93** — the shape of
the work, in rough groups:

- object protocol: `PyObject_Call`, `_CallFunctionObjArgs`, `_GetAttr(String)`,
  `_SetAttr(String)`, `_Hash`, `_IsTrue`, `_RichCompareBool`, `_Vectorcall`,
  `_VectorcallMethod`, `Py_TYPE`
- long/number: `PyLong_As{LongLong,Ssize_t,UnsignedLong,UnsignedLongLong}`,
  `PyLong_From{LongLong,Size_t,UnsignedLong,UnsignedLongLong}`, `PyLong_Check(Exact)`,
  `PyNumber_{And,Index,Invert,Long,Rshift}`
- unicode: `PyUnicode_{Compare,CompareWithASCIIString,Decode,DecodeUTF8,FromFormat,InternInPlace,CheckExact}`
- dict/tuple/bytes/bytearray: `PyDict_{Contains,GetItemString,GetItemWithError,SetItemString,Update}`,
  `PyTuple_{Check,Size}`, `PyBytes_{AsStringAndSize,CheckExact}`, the `PyByteArray_*` four
- errors: `PyErr_{ExceptionMatches,Fetch,Restore,Format,GivenExceptionMatches,WarnEx,WarnFormat}`
- import/module/sys: `PyImport_{AddModule,GetModuleDict,ImportModule}`,
  `PyModule_{GetDict,NewObject}`, `PySys_GetObject`
- memory: `PyMem_Malloc`, `PyMem_Realloc`, `PyMemoryView_FromMemory`
- the tail nobody should implement yet: `PyEval_EvalCode`, `Py_CompileString`,
  `PyTraceBack_Here`, `PyInterpreterState_*`, `PyType_GetQualName`

Many are referenced from Cython utility code that a given module never
executes, so the honest sequencing is: declare all of them, implement on
first LINK failure, and let anything unimplemented fail at link with its own
name (the ticket's existing rule — "never silently do nothing at run time").

### Recommended milestone split

- **M5a** — `-X binding=False` + `Py_LIMITED_API`, one arithmetic `def`.
  The 20 identifiers, the 4 headers, and however many of the 93 functions the
  link actually demands. This is the rung that proves the Cython shape works.
- **M5b** — drop `binding=False` (CyFunction: a heap type via `PyType_FromSpec`,
  `tp_descr_get`, GC slots). This is where the type-object layer stops being
  avoidable.
- **M5c** — a `cdef class`, and a real Cython-built package from PyPI.

M5b is the honest boundary of "Cython support"; M5a is a weekend and unlocks the
measurement loop for the rest.

### Reproducing

```sh
python3 -m venv v && v/bin/pip install cython
v/bin/cython -3 -X binding=False -o cyadd_nb.c cyadd.pyx
gcc -fsyntax-only -w -DPy_LIMITED_API=0x030c0000 \
    -I <stub-headers> -I lib/cpyext/include -I lib/crtl/include cyadd_nb.c
```

Use **gcc** for the header-surface inventory, not cfront: it reports `#error`
and gives one diagnostic per missing name. Switch to cfront once the surface is
declared — from there the walls are C-frontend gaps and link failures, which is
what cfront is the right tool to find.


## 2026-08-03 — M5a LANDED. A Cython-generated module compiles, inits and RUNS.

Cython 3.2.9's unmodified output for a 6-line `.pyx` — 6057 lines — is compiled
by cfront against pxx's own `Python.h`, initialised through real PEP 489
multi-phase init, and its functions called. Verified against the oracle the
milestone asks for: the SAME generated C, built as a normal CPython 3.12
extension in a venv, gives identical results.

```
cyadd(20,22)=42  cyadd(-5,5)=0  cyadd(1000000,2000000)=3000000
cyfact(0)=1  cyfact(6)=720  cyfact(10)=3628800  cyfact(12)=479001600
```

`test/test_cpyext_cython.npy` + `test/nilpy_units/{cyadd_ext.pas,
cyadd_ext_host.c,vendor/{cyadd.pyx,cyadd_cython.c}}`, wired into
`make test-nilpy`.

### What the scoping pass got wrong, and it is worth recording

The scoping section above predicted M5a would be the ~20 identifiers plus the
75 functions, with the module-DICT and function-object work deferred to M5b.
That was wrong in an instructive way: **Cython 3 emits an EMPTY `m_methods`
table.** Its module-level `def`s are registered from the `Py_mod_exec` slot into
the module dict. So the M1-M4 route — walk the static PyMethodDef table — finds
nothing, and a module that init'd "successfully" had zero functions. Silently.

The type-object work stayed deferred (there are still no heap types), but three
M5b-shaped pieces moved into M5a because nothing works without them:

1. **Real PEP 489 init.** `PyModuleDef_Init` no longer collapses to
   `PyModule_Create2`: it runs `Py_mod_create` (synthesizing the module SPEC
   that importlib normally supplies — generated code reads only `spec.name`),
   then every `Py_mod_exec` in order, failing if one does.
2. **Attributes and the module dict.** `PyObject` gains `ob_attrs`; modules,
   specs and function objects carry a real dict. Everything else still raises
   AttributeError, which is the correct Python answer, not a placeholder.
3. **Builtin-function objects** (`PYOBJ_CFUNC`) via `PyCFunction_New(Ex)`, and
   `PyObject_Call` over them — including **METH_FASTCALL**, which is the common
   path (not an optimisation) once the claimed version is 3.12+.

### Four walls, each with its own lesson

- **`zlib.decompress` at module init.** Cython 3.2 compresses its string tables
  by default and decompresses them with a LIVE zlib module during init. Needs
  `-DCYTHON_COMPRESS_STRINGS=0`. A generated-code default can require an
  importable stdlib module at import time — worth checking for on every future
  package.
- **The CO_* flags.** Under `Py_LIMITED_API`, CPython does not expose them, so
  Cython falls back to `PyImport_ImportModule("inspect")` and reads them as
  attributes at run time. No runtime without an importer can satisfy that, so
  our `Python.h` DELIBERATELY diverges and defines them unconditionally. They
  are fixed published constants, not machinery.
- **`PyImport_AddModule` does not import.** It returns the module of that name
  or CREATES an empty one. Honouring that exactly (rather than raising
  ImportError) is what makes `builtins` and Cython's own `cython_runtime`
  scratch module work with no importer at all.
- **`PyErr_Fetch`/`Restore` must preserve the MESSAGE.** They did not, and the
  first failing init reported an empty error — the message was destroyed by the
  traceback builder's own fetch/restore round trip. Fetch now hands the message
  back as a real `str`. Directly cost an hour of chasing the wrong thing.

Also: `Py_CompileString` and `PyTraceBack_Here` were moved OUT of the
stop-the-program set. Their only real caller is Cython's traceback DECORATOR,
which runs after an exception has already happened; stopping there replaces a
reportable error with a message about tracebacks. They now fail and let the
caller restore the original exception. The distinction — "unsupported and
load-bearing" vs "unsupported and decorative" — is the useful one.

### Filed while doing this

- [[bug-cfront-error-directive-silently-ignored]] (prio 75) — `#error` compiles
  clean; this is what made the very first measurement lie.
- [[bug-cfront-undeclared-type-in-cast-treated-as-zero]] (prio 65) — an
  undeclared TYPE in a cast is a warning and evaluates to 0, so a
  function-pointer cast became null and the program segfaulted far away. gcc
  errors, with a did-you-mean that was the whole diagnosis.

### Remaining, for M5b

- `-X binding=False` is still required at generation time. Dropping it needs
  CyFunction: a heap type via `PyType_FromSpec`, `tp_descr_get`, GC
  traverse/clear, vectorcall. That is the honest boundary of "Cython support".
- `PyObject_CallFunctionObjArgs` is still a stop (needs an argument tuple built
  from a `va_list`); nothing generated has reached it.
- Keyword arguments through the fastcall path are refused rather than
  mis-passed — needs the `kwnames` tuple.
- A `cdef class`, and a real Cython-built package from PyPI, are M5c.

## 2026-08-06 — M5b PART 1: keyword arguments and the variadic call form

Two of M5b's three "Remaining" items done; CyFunction (`-X binding=False`) is
untouched and remains the honest boundary of Cython support.

**Keyword arguments through the fastcall path** now work instead of being
refused. The vectorcall layout puts the keyword VALUES in the same array after
the positional ones, described by a `kwnames` tuple — so keywords need no
separate channel, they ride past `nargs`. `PyObject_Call` builds the names tuple
and the value tail in ONE `PyDict_Next` walk, so the two cannot drift apart.
`BoundParamIsRef`-style care was not needed here, but the ordering was: see
below.

**`PyObject_CallFunctionObjArgs`** is implemented — NULL-terminated varargs into
a positional tuple, two `va_start` passes (the count has to be known to size the
tuple). It was a hard stop; nothing had reached it, and now the test does.

### The oracle, and why `cysub` exists now

`test/nilpy_units/vendor/cyadd.pyx` gained `def cysub(a, b): return a - b` and
was regenerated with the README's exact recipe. Before changing it, that recipe
was checked to reproduce the vendored 6057-line file **byte-for-byte** with the
freshly installed Cython 3.2.9 — so the regeneration is faithful and not a
version drift.

`cysub` is not padding. `cyadd` is COMMUTATIVE, so a `kwnames` tuple whose order
disagreed with the values it describes would still produce the right sum and the
bug would have been invisible. `cysub(b=8, a=30)` is 22 if the pairing is right
and -22 if it is swapped.

The oracle is the real thing, not expectation: the same vendored generated C was
built with gcc against `/usr/include/python3.12` into a real `.so` and imported
by CPython. All six behaviours (positional, all-keyword, reversed-keyword,
mixed, `CallFunctionObjArgs`, unknown-keyword TypeError) match it.

### The actual bug this uncovered: a STALE PENDING ERROR after successful init

The kwargs code was right on the first build, and the all-keyword calls still
failed — while the same call with one positional argument worked. Measured
rather than reasoned (a temporary probe printing `__pxx_PyErr_Message()`): the
message was **"inspect"**.

Cython's `__Pyx_init_co_variables` calls `PyImport_ImportModule("inspect")`
**unconditionally**, then only reads the result for `CO_*` flags it could not get
as macros. Our `Python.h` deliberately defines all of them (the M5a note above
explains why), so every use is preprocessed out, its `result` stays 1, and the
failed import's ImportError is simply **abandoned**. Under real CPython the
import succeeds, so no extension ever notices.

Leaving it pending is not harmless: the next Cython code to consult
`PyErr_Occurred()` as its own error check fails on somebody else's stale error.
Only the all-keyword path reached such a check, which is exactly why the failure
looked like a keyword bug and was not one.

Fixed at the boundary that knows init succeeded: `PyModuleDef_Init`'s exec-slot
runner clears a pending error after a slot returns success. A successful init
that leaves an error set is the extension violating the contract.

**Generalisable warning for M5c and any future package:** an extension may leave
a pending error behind a successful init, and the symptom surfaces arbitrarily
far away in an unrelated call. This is the second time a Cython
"works under CPython because a stdlib module happens to be importable"
assumption has cost real time — the first was `zlib.decompress` at init
(M5a). Worth checking for deliberately on each new package.

### Also filed

- [[bug-cpyext-pyerr-format-prints-U-and-S-literally]] (prio 50) —
  `PyErr_Format` delegates to `vsnprintf`, which does not know CPython's `%U` /
  `%S` / `%R` / `%A`. The unknown-keyword message reads `'%U'` instead of `'c'`,
  and because those specifiers consume no `va_arg`, anything after one of them
  reads a misaligned argument. `PyErr_WarnFormat` has the same body and bug.

### Still remaining for M5b/M5c

- `-X binding=False` is still required. Dropping it needs CyFunction: a heap type
  via `PyType_FromSpec`, `tp_descr_get`, GC traverse/clear, vectorcall.
- A `cdef class`, and a real Cython-built package from PyPI (M5c).

## 2026-08-08 — M5b/M5c SCOPING: the CyFunction surface, measured

`-X binding=False` is the last generation-time flag. Dropping it was estimated
before as "a heap type via PyType_FromSpec, tp_descr_get, GC traverse/clear,
vectorcall"; here is the actual list, taken the same way the M5 scoping pass
was — regenerate WITHOUT the flag, preprocess with the two required `-D`s so
only LIVE code counts, and diff the `Py*` identifiers against what
`lib/cpyext/include/**` declares.

```sh
v/bin/cython -3 -o cyadd_binding.c cyadd.pyx          # note: no -X binding=False
gcc -E -DPy_LIMITED_API=0x030c0000 -DCYTHON_COMPRESS_STRINGS=0 \
    -Ilib/cpyext/include -Ilib/crtl/include cyadd_binding.c -o cyadd_binding.i
grep -oE '\b(Py|_Py)[A-Za-z0-9_]*' cyadd_binding.i | sort -u > used.txt
grep -oE '\b(Py|_Py)[A-Za-z0-9_]*' lib/cpyext/include/*.h | sed 's/^[^:]*://' | sort -u > have.txt
comm -23 used.txt have.txt
```

8224 generated lines against 6212 with the flag, and **50 missing identifiers**.
`structmember.h` is a 51st gap of its own kind: Cython includes it
unconditionally (IncludeStructmemberH.proto) even under the limited API where
every consumer of it is preprocessed away, so the header must EXIST but only
`PyMemberDef`'s layout and the `T_*`/`READONLY` codes have to be right. Added
in this pass; it is the only part of M5b that is already done.

The 50 split into three groups, and the ordering between them is forced:

**1. Heap types — the real work.** `PyType_Spec`, `PyType_Slot`,
`PyType_FromMetaclass`, `PyType_GetSlot`, `PyType_GetFlags`, `PyType_Modified`,
`PyType_HasFeature`, `PyType_Type`, `PyType_Check`, `PyObject_TypeCheck`,
`PyObject_HEAD`, `PyGetSetDef`, the `Py_tp_*` slot ids (base, call, clear,
dealloc, descr_get, getset, methods, repr, traverse) and the `Py_TPFLAGS_*`
bits. Today `PyTypeObject` is a stub carrying `tp_name` and nothing else —
identity only, no slots — so this is an object-model change, not a set of
functions. It also brings instances whose layout the EXTENSION owns:
`tp_basicsize` bytes with our header at offset 0, which is what
`offsetof(PyCFunctionObject, m_module)` in the member table is reading.

**2. GC.** `PyObject_GC_New/Del/Track/UnTrack`, `Py_VISIT` (12 uses, the most
of anything here), `PyObject_ClearWeakRefs`. Our runtime is refcounted with no
cycle collector, so these can be honest no-ops around the allocation — but they
must exist and `Py_VISIT` must expand to something that compiles and does not
walk a null.

**3. Leaf functions — mechanical.** `PyCallable_Check`, `PyDict_Check`,
`PyErr_NoMemory`, `PyObject_CallFunction`, `PyObject_CallObject`,
`PyObject_CallMethodObjArgs`, `PyObject_HasAttr`, `PySequence_GetItem`,
`PyTuple_Pack`, `PyTuple_GetSlice`, `PyObject_GenericGetDict/SetDict`,
`PyCFunction_GetFlags/GetSelf`, `PyCMethod`, `PyImport_ImportModuleLevelObject`,
`PyVectorcall_Call`.

**There is no partial credit here** — the module does not compile until all 50
resolve, so group 3 cannot be landed and verified on its own against this
oracle. Anyone picking this up should build group 1 first, because it is the
one that can fail on design rather than on typing.

`PyInit_cyadd` in the raw diff is a false positive: the extension defines it.

## 2026-08-08 — M5b LANDED. `-X binding=False` is gone; heap types are real.

Cython 3.2.9's **default** output — no `-X` flag at all, 8224 lines from an
11-line `.pyx` — compiles under cfront, initialises, and its module-level
`def`s are genuine `cython_function_or_method` objects: instances of a heap
type built from a `PyType_Spec` through `PyType_FromMetaclass`, with `tp_call`,
`tp_descr_get`, a getset table and a member table declaring
`__vectorcalloffset__`.

Verified against the oracle the milestone asks for — the SAME generated C built
with gcc against `/usr/include/python3.12` and imported by real CPython 3.12.
All eighteen behaviours match, including the five that are the actual proof:

```
type(cyadd).__name__          cython_function_or_method
cyadd.__name__                cyadd
cysub.__qualname__            cysub
cyadd.__code__.co_varnames    a,b
cyfact.__code__.co_varnames   n,i,r
```

Those five exist because **every arithmetic result reads the same with the flag
or without it**. M5a's thirteen assertions cannot tell a CyFunction from a
plain builtin function, so re-adding `binding=False` by accident would have
failed nothing. Introspection is the only observable that distinguishes them,
which is why the test now reaches for `__code__` at all.

### The object-model change

`PyTypeObject` was a `tp_name` and nothing else. It is now a real `PyObject`
(kind `PYOBJ_TYPE`) carrying basicsize, flags, a borrowed slot array, `tp_base`
and the three instance offsets — because generated code puts type objects in
tuples, decrefs them, and reads `__basicsize__` off them. Instances are kind
`PYOBJ_INST`: `tp_basicsize` zeroed bytes with our header at offset 0, which is
exactly what `PyObject_HEAD` promises and what `offsetof()` in a member table
measures. `ob_ptr` doubles as `ob_type` for both kinds, so no other kind grew.

Three properties are deliberate and written into the header rather than left to
be discovered:

- **Slots are not inherited.** `tp_base` is recorded and `PyObject_TypeCheck`
  walks it, but no lookup falls through to a base; there is no MRO and no
  metaclass dispatch. Every type here is built whole from one spec, which is
  what the limited API asks of an extension anyway.
- **Types are immortal.** Static ones are process-global; a heap type is cached
  in Cython's shared-ABI module for the life of the program and borrows its
  slot array from a static spec. `Py_DecRef` refuses them outright rather than
  relying on a large refcount, so a stray decref cannot reach one.
- **There is no cycle collector**, so `PyObject_GC_Track`/`Py_VISIT` are
  genuine no-ops rather than stubs standing in for something missing.

**The limited API's one channel for instance offsets is the member table.** A
spec cannot state `tp_dictoffset` / `tp_weaklistoffset` /
`tp_vectorcall_offset` directly — CPython's documented route is a
`Py_tp_members` entry named `__dictoffset__` / `__weaklistoffset__` /
`__vectorcalloffset__`, which `PyType_FromMetaclass` now absorbs. Miss that and
`PyVectorcall_Call` has nowhere to find a CyFunction's `func_vectorcall`, so
every call to a Cython function goes looking for a slot that is nowhere. This
is the one piece where "read the spec" and "guess" diverge completely.

### Four walls, and what each one taught

- **`inspect` again, now FATAL rather than latent.** M5b part 1 fixed a *stale*
  ImportError from Cython's unconditional `PyImport_ImportModule("inspect")` by
  clearing it once init succeeded. With `binding=True` the generated code grows
  an **unguarded** `if (PyErr_Occurred()) goto error` a few lines later, so the
  same abandoned error now stops the module from initialising at all — the
  third time this one import has cost real time.
  The repair went to the actual source: that dead call exists **because of our
  own divergence** (this header defines the `CO_*` flags, so every read of
  `inspect` is preprocessed out and `result` is assigned 1 unconditionally).
  `inspect` is therefore registered as an EMPTY built-in module — observationally
  identical to CPython for the code that remains, an honest AttributeError for
  anything that really reads an attribute, and never a wrong value.
- **`types` is not optional either.** Cython caches `types.MethodType` at init
  and does not defend against the import failing. Registered, along with
  `types.CodeType` — and CodeType is genuinely CONSTRUCTED, because under the
  limited API `PyCode_New` is hidden and Cython builds code objects by CALLING
  the type with the 18-argument 3.11+ signature. That forced `type_call`
  (Py_tp_new → Py_tp_init, as CPython's `type_call` does) and a real code
  object storing each argument under its CPython name. With `binding=True`
  code objects are not decoration: `__Pyx_CreateCodeObjects` runs at module
  exec and a NULL aborts init.
- **`Py_BuildValue` silently truncated past eight values.** The item buffer was
  a fixed 8 with `n < 8` in the LOOP CONDITION, so a longer format quietly
  dropped the tail. Nothing had ever passed more than eight; the 18-argument
  code-object constructor is the first caller, and it would have built a wrong
  object rather than failing. Now sized from the format, with an unsupported
  letter reported instead of ignored.
- **`PyBytes_FromStringAndSize(NULL, n)` segfaulted.** CPython documents a NULL
  pointer as "allocate n bytes, contents are the caller's problem", and that is
  how generated code gets a writable bytecode buffer. Same for
  `PyUnicode_FromStringAndSize`. Both now allocate and zero.

### One decision worth stating: `self` is OWNED

`PyCFunction_NewEx` ignored its `self` argument entirely (M5a had no bound
builtins). CyFunction needs it — it passes ITSELF as self and reads it back in
every vectorcall wrapper — so it is now stored, and stored **owned**.

That closes a cycle this runtime cannot collect: the function object owns its
PyCFunction, whose self points back. Real CPython has the identical cycle and
pays for it with its GC, which is precisely why `CyFunction` carries
`Py_TPFLAGS_HAVE_GC` and a traverse slot. The alternative — a borrowed self —
has no leak but dangles the moment any bound method outlives its receiver, and
a dangling pointer is a silent wrong answer. A bounded leak of module-level
function objects is the cheaper failure and the honest one to take.

### Also new

`dict` gained real METHOD dispatch (`setdefault` today). Under the limited API
Cython cannot touch dict internals, so it emits an actual method call through
`PyObject_VectorcallMethod` — and that call is load-bearing: the shared-ABI
type cache publishes every heap type through it, so a dict with no methods
means no Cython type is ever registered. The mechanism is the ordinary
`PyCFunction_NewEx` one, so the next method is one table entry.
`PyObject_Vectorcall` and `PyObject_VectorcallMethod` are implemented rather
than hard stops; `PyType_GetQualName` is real now that heap types exist.

### Still remaining (M5c)

- A `cdef class`, and a real Cython-built package from PyPI.
- `tp_descr_get` is INSTALLED but never fires: nothing here reaches a function
  through a type, so no bound method is ever built and `types.MethodType` is an
  identity only. A `cdef class` with methods is what will first need it, and
  that is the point where bound methods (and the `self` cycle above) stop being
  hypothetical.
- No cycle collector, stated once more because a `cdef class` allocating
  instances in a loop is where the bounded leak stops being bounded.
