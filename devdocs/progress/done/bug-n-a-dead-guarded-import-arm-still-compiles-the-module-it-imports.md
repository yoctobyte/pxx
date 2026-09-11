---
slug: bug-n-a-dead-guarded-import-arm-still-compiles-the-module-it-imports
title: "An import standing after a failed one in the same guarded arm still compiled its module, and that module's errors escaped"
track: N
type: bug
prio: 80
status: done
created: 2026-09-11
found: 2026-09-11
found-by: frankZ
owner: frankZ
tags: [nilpy, imports, lekkerzeilen, fallback-import]
blocked-by: []
summary: "FIXED 2026-09-11. `try: import ctypes / from . import _ctypes_backend as _backend` -- the second import was resolved even though the first had missed, so a module CPython never imports was parsed and ITS errors killed the build. Reported as `pascal26:181:` with the dead module's line number and no file name, against a platform/__init__.py that is 150 lines long. NOT the sibling case PyParseFallbackImportTry's own header already documents and calls benign (a module resolved BEFORE the failing one stays loaded = unused weight in the binary); this is the opposite side of one statement and it is a wall, not weight. Only a SOFT IMPORT MISS inside the pulled module was absorbed -- a syntax error, an undefined name, or a member read on a qualifier that bound nothing all escaped, measured against CPython in four bodies for one dead module with CPython printing the handler's answer every time. Fixed at PyParseImportUnitAs, the single choke point every user-facing import arm goes through, driven by a new SoftArmDead flag set per statement from PyParseImportRun's own miss accumulator and restored on the way out, so a module pulled by a LIVE import may run its own guarded blocks without inheriting ours. Live-arm control in the same fixture: the arm whose guarded import RESOLVES must still compile its module and win, which is what stops the fix degenerating into `never resolve a guarded arm's module`."
---

# The shape, and it is lekkerzeilen's seam

```python
try:
    import ctypes                              # misses under NilPy
    from . import _ctypes_backend as _backend  # compiled anyway
except ImportError:
    from . import _pxx as _backend
```

CPython never imports `_ctypes_backend`: the arm dies at its first line. We
resolved every import in the arm regardless, so the module was parsed and its
own `ctypes.c_uint` was reported.

# What made it expensive rather than merely wrong

The error carries the DEAD module's line number and no file name
([[bug-n-an-error-inside-an-imported-module-is-reported-with-that-modules-line-number-and-no-file-name]]),
so it reads as a defect in the file you invoked. `platform/__init__.py` is 150
lines long and the reported line was **181**.

# Why a fixture built from import errors would have passed

A soft import miss inside the pulled module IS absorbed by the machinery under
test. Measured before the fix, one dead module, four bodies, CPython printing
the handler's answer for every one:

| dead module's body | before |
| --- | --- |
| `SHARED = 99` (well formed) | agrees with CPython |
| `def (((  broken syntax` | `unmatched opening parenthesis` |
| `import ctypes` + `X = ctypes.c_uint` | `no member c_uint came of the qualifier ctypes` |
| `SHARED = undefined_name_xyz` | `undefined variable (undefined_name_xyz)` |

So the fixture mixes a member read and an undefined name on purpose. A fixture
whose dead module only failed to IMPORT would have been green throughout.

# The fix

`SoftArmDead` (defs.inc), set in `PyParseImportRun` per statement as
`savedArmDead or (SoftUnitResolve and runMissed)` and restored on exit; read in
`PyParseImportUnitAs`, which answers `SoftUnitMissed := True` and does not probe
the filesystem. `SoftUnitMissed` rather than silence, because the arm must keep
reading as missed for the alias rollback that follows
([[bug-n-a-dead-guarded-import-arm-still-binds-its-unit-alias]], which is this
bug's sibling in the same routine and was fixed the same night).

Only in a SOFT run: outside a `try:` a miss is a hard error at the import
itself, so there is no later statement to protect.

# What it moves, and what it does not

`lekkerzeilen/platform/__init__.py` written in the `import ... as` spelling
advances from `_ctypes_backend.py:181` to its own line 108 — `getattr(_backend,
"open_audio", None)`. Modules-compiling on the corpus: **0**, measured, and
stated here because that is the honest number. The worth is a wall removed from
in front of a p75 design fork and a whole class of misattributed diagnostics.

See [[bug-n-a-module-bound-by-an-import-is-not-a-value]] for the fork this
unblocks: with the seam in the alias spelling, `getattr` over a unit alias is
now the ONLY remaining construct in that file, which answers by measurement a
question that ticket could only argue about.
