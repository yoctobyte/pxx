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
