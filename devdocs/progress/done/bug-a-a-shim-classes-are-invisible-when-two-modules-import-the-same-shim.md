---
track: A
prio: 65
type: bug
blocked-by: []
summary: "When two NilPy modules in one build both `import <shim>` (a mimic_-mapped module), the shim's CLASSES stop resolving in the imported module — `codecs.CodecInfo(...)` reports `undefined variable (CodecInfo)`. The unit alias and the shim's PROCS still resolve, so `codecs.lookup(...)` in the same file is fine. Top wall of the NilPy corpus ladder: 7 of 48 files."
status: done
owner: frank2-7e
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

## FIXED 2026-08-18 (frank2-7e, combined A+N) — the uses edge, not the guard

### The trigger, refined — the shape of the repro is load-bearing

The title's "two modules import the same shim" is necessary but not sufficient,
and the weaker reading is what made this look non-reproducible when a peer first
checked it. Measured row by row:

| shape | pre-fix |
| --- | --- |
| other module imports the shim, uses nothing | resolves |
| other module uses a shim **PROC** (module level or in a function) | resolves |
| other module uses a shim **CLASS** | **FAILS** |
| other module uses the class, entry module uses only a PROC | **FAILS** |
| the class used in the **ENTRY** module alone | resolves |

So: the entry module's import is what marks the shim's SPELLING compiled, and the
defect then bites whichever OTHER module uses the shim's **class**. A repro where
the entry module uses the class passes while the bug stands, because the entry
module is exactly where the real edge did get recorded.

That is the corpus shape precisely, and it explains the row size in one sentence:
`webencodings/x_user_defined.py` does `class Codec(codecs.Codec)` at module
level, and `__init__.py` imports it — **one imported sibling subclassing a shim
class, behind 8 files.**

### Root cause — measured, and it overturned my own filed hypothesis

I filed this with `FindUClassNonRecord` as a by-elimination guess and a
`VisibilityAllows` chain derived by READING the source. A `PXXDBG a.qual` probe
at the guard printed the actual state:

```
control  curname=xud unitname=mimic_codecs clsunit=615 nonrec=131 visible=TRUE
repro    curname=xud unitname=mimic_codecs clsunit=613 nonrec=-1  visible=FALSE
```

Both arrangements resolve the qualifier to `mimic_codecs` **and find the class
there** via `FindUClassInUnit`. The only difference is visibility — which proves
the class row was never missing and kills the guard-level reading outright.

`ParseUsesUnit` records the uses edge against `strIdx`, the **spelling**
(`codecs`), and `guardIdx` is that same spelling. On the FIRST import that is
harmless: the shim branch re-enters through `ParseUsesUnit('mimic_' + lo)`, which
records the real edge to `mimic_codecs` on the way in. A SECOND importer never
reaches that branch — the spelling is already in `CompiledUnits`, so it takes
`if isCompiled then Exit` (`parser.inc:33518`) holding an edge to a name nothing
is declared under. `DeclVisible` then fails and `FindUClassNonRecord` skips the
row.

The proc/class asymmetry is a **qualified/flat** split: a qualified PROC names
its unit and never consults the visibility-filtered scan. The surviving procs
were not special — they simply never went through `DeclVisible`.

### The fix, and the fix that was NOT taken

On the already-compiled exit, resolve the spelling through the alias chain and
record the edge to the REAL unit.

The tempting alternative was to make the guard at `parser.inc:10014` ask
`FindUClassInUnit` the way the ctor path at `pyparser.inc:6173` already does.
**It would have compiled the repro and left every other visibility-filtered
lookup in a second importer broken** — a passing test certifying a resolution
hole. Only the probe separated them.

This is the same defect and the same fix as the duplicate-`.py` arm ~700 lines
below (search `pyDupIdx`), whose comment already recorded the answer the first
time round: *an alias answers a QUALIFIER, it does not make a module's symbols
VISIBLE.* Two arms of one concept where one already knew — so this deletes a
case rather than adding a mechanism.

### Corpus effect — reported past-vs-onto, and the compile count did NOT move

Clean A/B: only this commit touches `compiler/**` since pin v348, so
pinned-vs-HEAD isolates it exactly. Same corpus, same `lib/rtl`, `-Fu` both
roots, `tools/nilpy_ladder.py`.

| | v348 (control) | HEAD + fix |
| --- | ---: | ---: |
| compile | 6/48 | **6/48 — unchanged** |
| `undefined variable (CodecInfo)` | **8** | **0 — gone from the table** |
| `undefined variable (yield)` | 3 | **11** |

Every other row is identical, and 3 + 8 = 11: the eight files moved wall-to-wall.

**The top wall is cleared and not one additional file compiles.** That is the
honest headline. This clears a wall; it does not open the pipeline — the
compounding recorded in [[feature-nilpy-yield-outside-a-for-loop]], now
demonstrated rather than predicted. `yield` is now the largest row on the board
by nearly 3x, which is the argument for scheduling it alongside the module shims
rather than behind them.

### Regression test

`test/test_nilpy_shim_class_in_imported_module.npy` +
`test/nilpy_units/shimclassuser.npy`, wired into `test-nilpy` (which enumerates
and never globs, so it is named explicitly).

Deliberately built in the **strong** shape — class used in the imported module,
entry module touching only a proc — because the weak shape passes while the bug
stands. Verified both ways: **fails on pinned v348** with `undefined variable
(CodecInfo)`, passes at HEAD.

### Gate

`make compiler/pascal26` (fixedpoint, converged) + the 7-row boundary table + the
4 corpus files + the new test failing pre-fix and passing post-fix +
`tools/gate.sh quick` GREEN. No pin needed — `parser.inc` only, nothing in
`compiler/builtin/**`.

## Log
- 2026-08-18 — resolved, commit 68b67a53a.
