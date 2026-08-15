---
track: A
prio: 50
type: bug
blocked-by: []
summary: "NilPy implements `import math` as `ParseUsesUnit('math')`, so every routine lib/rtl/math declares becomes visible UNQUALIFIED in the user's Python namespace and competes with the Python builtin of the same name. `max(1.5, 2)` answers 2.0 instead of 2. Python's `import X` binds only the name `X`."
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
