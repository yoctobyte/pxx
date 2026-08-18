---
track: A
prio: 65
type: bug
blocked-by: []
summary: "When two NilPy modules in one build both `import <shim>` (a mimic_-mapped module), the shim's CLASSES stop resolving in the imported module — `codecs.CodecInfo(...)` reports `undefined variable (CodecInfo)`. The unit alias and the shim's PROCS still resolve, so `codecs.lookup(...)` in the same file is fine. Top wall of the NilPy corpus ladder: 7 of 48 files."
status: backlog
owner: unassigned
---

# A shim's classes are invisible when two modules import the same shim

- **Type:** bug (name resolution) — **Track A** (`compiler/parser.inc`, and/or the
  shim/alias registration in `compiler/symtab.inc`)
- **Found:** 2026-08-18 by frank2-7e (Track N) running the corpus ladder A/B for
  [[feature-nilpy-thirdparty-libraries-as-targets]].
- **Filed, not fixed:** the deciding guard is in `parser.inc`, a shared Track A
  file. Track N does not edit it.
- **Measured at:** HEAD `c7974b6af`, self-hosted fixedpoint build. Reproduces on
  pinned v347 (`08bdf2729`) too, so it is not new.

## Why it matters

**Top wall of the ladder: 7 of 48 corpus files**, all of tinycss2 + webencodings,
through `webencodings/x_user_defined.py:50`. It is the largest single row in the
current table and the only one above 4.

## Minimal repro — two files

`pk/xud.py`:

```python
import codecs
thing = codecs.CodecInfo(name='x', encode=None)
```

`pk/__init__.py`:

```python
import codecs                 # <-- REMOVE THIS LINE AND IT COMPILES
from .xud import thing
print("ok")
```

```
pascal26 -Fupk -Fupk/pk -Fulib/rtl pk/__init__.py out
  -> pascal26:2: error: undefined variable (CodecInfo)
```

Delete the importer's `import codecs` and it compiles. Nothing else changes.

## The boundary, measured — most of the obvious suspects are NOT it

Each row varied one thing against the repro above:

| shape | result |
| --- | --- |
| importer does not import the shim | **OK** |
| importer imports the shim | **FAILS** |
| relative (`from .xud`) vs absolute (`from xud`) | no effect |
| top-level import vs function-local import | no effect |
| imported module calls a shim **FUNCTION** (`codecs.lookup(...)`) | **OK** |
| imported module constructs a shim **CLASS** | **FAILS** |
| imported module imports the shim but does not use it | OK |
| two modules both importing an ordinary **user** module with a class | **OK** |

So it is specific to a **shim-aliased** module (`codecs -> mimic_codecs`), and
specific to its **classes**. An ordinary duplicate import is fine, which rules
out "duplicate import" as the bug on its own.

## Where it goes wrong

`parser.inc:10014` is the guard that turns `mod.Class(...)` into a NilPy
qualified construction:

```pascal
(FindUClassNonRecord(GetTokenStr(TokPos + 1)) >= 0) and
(FindSym(CurTok.SVal) < 0) and (FindUnitOrAlias(CurTok.SVal) >= 0)
```

When it fails the expression falls through to the ordinary path, which is why the
diagnostic is `undefined variable (CodecInfo)` and **not** `class not found` —
the constructor path at `pyparser.inc:6173` is never entered at all. That
distinction is the quickest way to confirm you are in the right place.

Of the three conjuncts:

- `FindUnitOrAlias('codecs')` is fine — the qualified **proc** path shares it and
  `codecs.lookup(...)` works in the failing build.
- `FindSym('codecs')` is **not** the culprit. I tested it directly: `thing =
  codecs` reports `undefined variable (codecs)` in BOTH the passing and failing
  arrangements, so the import does not create an ordinary symbol either way.
  Recorded so nobody re-tests it — it was my first hypothesis and it is wrong.
- By elimination: **`FindUClassNonRecord('CodecInfo')` returns < 0**. The shim's
  classes are not in the class registry in that context, while its unit alias and
  its procs are.

Left to A: whether the fix is at the guard or in the shim/alias registration that
should have put `mimic_codecs`'s classes in scope for the second module. I did
not narrow past this point because the next step is instrumenting a shared file.

## Note on attribution — a done ticket is credited with this row and should not be

The published ladder table
([[bug-t-the-ladder-scan-passes-only-one-root-so-cross-package-imports-read-as-walls]])
attributes the `CodecInfo` row (7 files) to
[[bug-n-a-temporary-receiver-resolves-to-the-shim-type-not-the-user-class]].
That ticket is **done and inside pin v347**, and the row is unchanged at 7 on
both the pinned and HEAD scans — so it cannot be the cause. Different mechanism:
that one was a qualifier leaking into a nested construction's arguments; this one
is the qualified construction never being recognised. The attribution should be
corrected wherever it is cited, or the next reader will treat this wall as
already fixed.
