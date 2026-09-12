---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`**` inside an IMPORTED .py never gets PyPowHook, for TWO independent reasons, and each one alone is sufficient: (1) the `pyWantsPow` token scan at `pyparser.inc:41694` runs before `PyParseImportRun` at 41769, so an imported module's tokens are not in the array being scanned; (2) an imported .py becomes a UNIT, and a unit's initialisation section runs BEFORE the main body where the assignment is emitted as the first statement — so import-time `**` cannot see the hook even when it IS installed. Both measured 2026-09-12 with a control: with `**` in main too, import-time printed 1.9952623149688793 and post-start printed CPython's exact 1.9952623149688795. Visible cost today is 1 ulp, NOT a crash — the raise this was found through (`0.0 ** fractional` -> `ValueError: math domain error`) was a missing row in `pypow_cx` and is fixed separately."
---

# An imported module's `**` is computed by the fallback, not by the RTL's `Power`

Found while running lekkerzeilen, which is how the severity got measured
correctly: the symptom was a crash, the crash was somebody else's bug, and what
is left here is a last ulp.

## Defect 1 — the scan runs before the imports

`compiler/pyparser.inc:41693`:

```pascal
  pyWantsPow := False;
  for i := 0 to TokCount - 2 do
    if (Tokens[i].Kind = tkStar) and (Tokens[i + 1].Kind = tkStar) then
```

`PyParseImportRun` is at 41769 and the install at 41796. So the scan answers
about the main module's tokens only.

**A contained fix is possible at 41796**, because by then the imports have been
parsed and the tokens exist — set `pyWantsPow` there too rather than moving the
scan. What makes it not purely mechanical is the `ParseUsesUnit('math')` pull
that sits INSIDE the scan at 41708: the comment above 41713 records that math
must be pulled BEFORE `ParseUsesUnitAmbient('pylib')` because the last unit
named wins a name and math's integer `Abs` otherwise hides pylib's float one
(measured: `abs(-1.5)` stopped resolving). So the scan cannot simply move down,
and the install site cannot simply pull math.

## Defect 2 — unit initialisation runs before the main body

The assignment is emitted as the program's FIRST statement (41796 onward,
`mainNode := PySeqAppend(mainNode, powAsgn)`). An imported `.py` is a unit, and
Pascal runs unit initialisation sections before the main body. So a module-level
`**` in an imported module executes with `PyPowHook = nil` regardless of
defect 1.

**Control, and it is what makes this a second defect rather than a restatement
of the first** — predicted before running that a `**` in the main module would
fix the imported one; it did not:

| where the `**` runs | printed |
| --- | --- |
| import time (module level, in the imported unit) | `1.9952623149688793` |
| after the program starts (same function, called from main) | `1.9952623149688795` |

CPython gives `...95`. Both rows are from one program with `**` in main, so the
hook WAS installed; only the ordering separates them.

## What the cost is, stated honestly

One ulp on a `**` in an imported module. The hookless path is
`PyMathExp(e * PyMathLn(b))`. It is not a crash and not an F-lane ticket by the
"rank the mechanism, not the datatype" test — the mechanism is a hook that does
not get installed — but the OBSERVABLE is a last digit, so do not rank it as
though it were the `ValueError` that led here.

## The regression fixture already exists and pins the FALLBACK, not this

`test/test_nilpy_pow_zero_base_in_an_imported_module.npy` (+ its aux module
`test/nilpy_pow0_mod.py`) deliberately contains no `**` of its own, because a
`**` in main would retire its four post-start rows. **It therefore passes both
before and after this ticket is fixed** — it measures `pypow_cx`'s arithmetic,
which is correct now. Fixing this ticket makes four of its rows stop reaching
that code at all; the import-time rows will still reach it until defect 2 is
also fixed. Anyone fixing either half should add a row asserting the
`...688795` value, which is the only thing that can observe the hook arriving.
