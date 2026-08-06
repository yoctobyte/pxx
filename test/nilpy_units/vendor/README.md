# Vendored extension source (cpyext M4)

`_speedups.c` is an **unmodified** copy of
[MarkupSafe](https://pypi.org/project/MarkupSafe/) 3.0.3's
`src/markupsafe/_speedups.c`, same filename, byte-identical content.
Fetched via `pip download markupsafe==3.0.3 --no-deps --no-binary :all:` on
2026-08-01.

License: BSD-3-Clause, Copyright 2010 Pallets — see `markupsafe_LICENSE.txt`
(copied verbatim from the same sdist).

Why this package for M4 ("a real extension from PyPI"): small (200 lines),
single file, no build-system magic, no numpy/buffer-protocol dependency,
widely used (a dependency of Jinja2/Flask), permissively licensed. It also
happens to exercise real-world API surface M1–M3 never needed: the
`PyUnicode_KIND`/`*_DATA` internal-unicode-representation API, multi-phase
module init (`PyModuleDef_Slot`, `PyModuleDef_Init`), `METH_O`, and
designated struct initializers in the vendored source itself — see the M4
comment atop `lib/cpyext/include/Python.h` for the exact API additions this
forced.

# Cython-generated source (cpyext M5)

`cyadd.pyx` is the input; `cyadd_cython.c` is **Cython 3.2.9's unmodified
output** for it (6212 lines from an 11-line `.pyx` — the boilerplate IS the
point of the milestone). Regenerate with:

```sh
python3 -m venv v && v/bin/pip install cython
v/bin/cython -3 -X binding=False -o cyadd_cython.c cyadd.pyx
```

License: the generated file is a derived work of the `.pyx` in this directory,
which is ours; Cython's own runtime snippets inside it are Apache-2.0.

Two flags are required at COMPILE time and are not optional:

- `-DPy_LIMITED_API=0x030c0000` — removes every direct-struct-layout
  dependency (`PyASCIIObject`, `PyListObject`, `PyLongObject`, `PyLong_SHIFT`,
  …). Those are exactly what pxx cannot honour, and the limited API is the
  contract that removes them. Measured: it cuts the missing-identifier count
  from 46 to 22.
- `-DCYTHON_COMPRESS_STRINGS=0` — Cython 3.2 defaults to zlib-compressed
  string tables and calls `zlib.decompress` **at module init**, i.e. it needs a
  live importable `zlib` module. Without this flag the module fails to
  initialise with `Failed to import 'zlib.decompress'`.

`-X binding=False` at GENERATION time drops Cython's CyFunction machinery (its
own heap type with `tp_descr_get`, GC traverse/clear, vectorcall). That is what
M5b is for; M5a deliberately does not need it.
