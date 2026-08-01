# cpyext — CPython C-API surface, compiled from source

`lib/cpyext` provides pxx's own `Python.h` (and the C runtime behind it) so a
CPython C-extension's SOURCE can be compiled by cfront and called from a NilPy
`.npy` program. This is explicitly NOT a loader for a prebuilt CPython `.so` —
see `devdocs/progress/working/feature-nilpy-cpyext-c-api-from-source.md` for
why that shortcut does not work (fixed struct offsets, inlined refcounting,
CPython-version-specific object layout).

- `include/Python.h` — the header an extension's C source `#include`s. Not
  ABI-compatible with real CPython; it is pxx's own minimal object model that
  happens to expose the same *source-level* API surface (same struct/function
  names an extension calls), so unmodified extension source compiles against
  it. Extend only as later milestones need more surface — the design intent is
  that an unimplemented API fails to **link** with a clear undefined-symbol
  name, never silently no-ops at runtime.
- `src/pyruntime.c` — the implementation behind that header: a tiny object
  model (long/tuple/module/none), refcounting, `PyArg_ParseTuple`,
  `PyModule_Create2`.

## Status (M1 "hello-ext")

Only the slice M1 needs: `PyObject`, `Py_INCREF`/`DECREF`/`XDECREF`,
`Py_None`, `PyModuleDef` + `PyModuleDef_HEAD_INIT`, `PyMethodDef` +
`METH_VARARGS`, `PyModule_Create`, `PyArg_ParseTuple` (format `"i"` only),
`PyLong_FromLong`/`PyLong_AsLong`, and enough of `PyTuple_*` to carry
positional args into a call. See `test/nilpy_units/hello_ext_module.c` (a
hand-written extension module in the real CPython boilerplate shape) and
`test/nilpy_units/hello_ext_host.c` (the embedding-style driver: discovers
`PyInit_hello_ext`, walks its `PyMethodDef` table, calls `add_one`) plus the
Pascal bridge unit `test/nilpy_units/hello_ext.pas` that NilPy's `import`
binds to directly (unit scope is flat — a plain `interface function` is
callable as `hello_ext.add_one(...)` with no extra registration step). The
module source is deliberately NOT named `hello_ext.c` — see the comment atop
`hello_ext.pas` for a real C-frontend resolver bug that name collision hit.

M2+ (argument/error formats, strings, containers, a real PyPI extension,
Cython output, buffer protocol) are tracked in the ticket above; not
attempted here.
