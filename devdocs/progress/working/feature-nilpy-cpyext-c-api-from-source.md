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
