---
track: N
prio: 65
type: feature
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
