---
track: A
prio: 50
type: bug
blocked-by: []
summary: "NilPy implements `import math` as `ParseUsesUnit('math')`, so every routine lib/rtl/math declares becomes visible UNQUALIFIED in the user's Python namespace and competes with the Python builtin of the same name. `max(1.5, 2)` answers 2.0 instead of 2. Python's `import X` binds only the name `X`."
status: done
owner: agent-acpn
---

# a NilPy `import` leaks the unit's names into the Python namespace

Split out of [[bug-nilpy-uses-math-breaks-abs-on-a-float]] on 2026-08-16, which
fixed the `abs` symptom at its intercept and left the cause standing.

## The rule being broken

In Python, `import math` binds exactly one name: `math`. It does **not** put
`floor`, `sqrt`, `pow` — or anything else — into the importing module's
namespace; that is what `from math import *` is for, and nobody writes it. In
NilPy the import is implemented as `ParseUsesUnit(impName)`
(`pyparser.inc`, the plain-import arm), which is Pascal's `uses`: every routine
the unit declares becomes visible unqualified and joins the overload set for
its name.

So a Python builtin now competes with whatever the RTL unit happens to declare,
and which one wins is decided by overload ranking — i.e. by argument widths and
declaration order in a file the user never opened.

## Measured

```python
import math
print(max(1.5, 2), min(2, 1.5))
```

| | CPython | pxx |
| --- | --- | --- |
| `max(1.5, 2)` | `2` | **`2.0`** |
| without `import math` | `2` | `2` |

CPython's max returns the ARGUMENT, preserving its type; math's
`Max(Double, Double)` returns a Double, so the int is silently widened. The
value is not wrong, the TYPE is — which is the kind that survives into a
`isinstance`/`%d`/dict-key further down.

`abs` was the loud member of the same family (`abs([-0.0][0])` printed a
pointer) and is fixed; `min`, `max`, `round`, `floor`, `ceil`, `sqrt`, `exp`,
`ln` and `power` are all declared by `lib/rtl/math.pas` and all have NilPy
builtins of the same name.

## Fix shape

Load the unit, do not publish its names. The visibility machinery landed
2026-08-15 (`DeclVisible` / `VisibilityAllows` / non-transitive uses) is the
place: a unit pulled by a NilPy `import` wants a QUALIFIED-ONLY mode, so
`math.floor(...)` resolves and bare `floor` does not see it. Everything NilPy
serves through a module qualifier keeps working; everything the Python builtin
surface owns stops being ambushed.

Do NOT do it per name at the intercepts. The abs fix did that on purpose,
because it was one call site and the value was actively wrong, and the write-up
says so — but there are ten names here and each intercept is a separate
mechanism. One qualified-only flag replaces all of them.

Check the fix against the whole `lib/rtl/math.pas` export list, not just `max`:
that is the ticket this one was split out of, making the same request one level
up.

## Test

`test/test_nilpy_abs_under_import_math.npy` already covers the abs half. The
min/max rows belong beside it once this lands.

## FIXED 2026-08-16 — load the unit, do not publish its names

A plain `import X` sets `PyImportPending`; the unit resolver's **Pascal branch**
alone marks the resolved unit qualified-only (`MarkUnitQualifiedOnly`). A `.py`
module import, a C-header import and every Pascal `uses` never reach that line
with the flag set, so nothing outside NilPy's plain-import path changes.

`DeclVisibleBareRoutine` is `DeclVisible` plus "…and not a qualified-only unit,
while NilPy USER code is being compiled". It is consulted at **FindProc's two
chain loops, the builtin-demotion scan, and `MatchEligBase`**.

### Two things this cost, both worth writing down

**It is ROUTINES only, and that was not the first design.** The rule started
inside `DeclVisible` itself, which hid the unit's classes and types too — and
`class D(mixinproto.Proto)` promptly stopped working: the base is REACHED
through the qualifier, but once it is a base its members are resolved by the
compiler, not by a name the user wrote, and hiding them broke inherited-method
lookup outright (`Before has no method Twice`). Types, constants and symbols are
the same case. Only a BARE ROUTINE NAME is what Python's import rule actually
governs, so the predicate moved out of `DeclVisible` and into the routine
lookups.

**`FindProc` is not where a call resolves.** With only the FindProc loops
patched, a bare `Power` was correctly hidden and `max(1.5, 2)` still answered
`2.0` — because a direct call site resolves through `MatchEligBase`, which is
exactly the blind spot `--warn-uses-leak`'s own comment three lines above it
records having had. Both had to be patched.

`QualNameLookup` turns the rule off for the frontend's own by-name lookups, so
`PyParseStdlibCall` still resolves `math.pow` to `Power` and `math.sqrt` to
`Sqrt` — naming the module is precisely what the import binds.

### Measured, all against CPython

```
import math
min(1.5, 2), max(1.5, 2), max(2, 1.5), min(2, 1.5)   1.5 2 2 1.5     was: 1.5 2.0 2.0 1.5
min(-0.0, 0.0), max(-0.0, 0.0)                       -0.0 -0.0       was: 0.0 0.0
abs(-1.5), abs(-0.0), abs(-3), round(2.5)            1.5 0.0 3 2
math.floor / ceil / sqrt / fabs / trunc / copysign / log / log10 / pi   all unchanged
Power(2.0, 3.0)                                      undefined variable (Power)   <- correct
```

The one row still divergent is `math.pow(2.0, 0.5)`, and it is not this: it is
[[bug-b-power-lost-an-ulp-on-a-half-integer-exponent]], filed earlier the same
day against Track B's Power rewrite.

### Unblocks

[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]] — its prototype is
measured (107/120 exact, worst 1 ulp) and was blocked first by `abs` and then by
`min`/`max`. Both walls are down. Whoever takes it should re-apply
`devdocs/dev/prototypes/nilpy-float-pow-via-rtl-power.patch` and re-run the
oracle rather than assume.

### Gate

`make compiler/pascal26` (self-host fixedpoint, byte-identical) + `tools/gate.sh
quick` GREEN. Verified by hand beyond the gate: every `.npy` test that imports a
Pascal unit (`mixinproto`, `sysutils`, `stdlib`, `tobjprobe`, the C-header one)
compiles and still answers, the multiple-inheritance test still prints its four
exact lines, the two-imported-bases refusal still refuses, and uforth.py still
compiles and runs. `test/test_nilpy_import_does_not_publish_names.npy` pins the
whole set against CPython, qualified spellings included.

## Log
- 2026-08-16 — resolved, commit e94b8cda3.
