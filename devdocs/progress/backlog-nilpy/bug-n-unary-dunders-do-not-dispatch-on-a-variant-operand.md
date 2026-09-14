---
type: bug
track: N
prio: 55
status: open
slug: bug-n-unary-dunders-do-not-dispatch-on-a-variant-operand
---

# `-v`, `~v` and `abs(v)` on a user class RAISE when the operand is a variant

The binary operator dunders have a runtime fallback for a VARIANT operand
(`pyadd_v` -> `PyVarUserArith` -> `PyUserArithCall1`, pylib.pas). The unary ones
do not, so the identical class works statically and fails through a parameter.

Measured 2026-09-14 at 17e5731a7, CPython as oracle, class declaring all four:

| expression | operand is a local with a static class type | operand is an unannotated PARAMETER |
|---|---|---|
| `-a`     | `2.0` (correct) | `TypeError: expected a number, got object` |
| `~a`     | (not measured)  | prints NOTHING and dies -- no diagnostic at all |
| `abs(a)` | (not measured)  | `TypeError: expected a number, got object` |
| `+a`     | -- | answers, but the right answer here COLLIDES with the no-op default, so this row proves nothing and is not a claim |

CPython answers all four.

## WHY THE VARIANT ARM IS THE ONE THAT MATTERS

A variant operand is not an edge case: an unannotated parameter, a for-loop
variable, a container element and an attribute are all variants, and ordinary
Python annotates none of them. `/home/neo/lekkerzeilen/lekkerzeilen/math3d.py`
has ZERO parameter annotations across the whole module and declares
`Vec3.__neg__` at line 59 -- so every `-v` in that package that crosses a
function boundary raises.

This is the same route trap as
`bug-n-a-user-operator-on-a-variant-operand-leaks-its-result`, found in the same
hour: the compile-time dispatch in the parser is correct and the runtime arm
behind it is not. A fixture written with annotated locals passes both.

## REPRO

```python
class V:
    def __init__(self, x=0.0):
        self.x = float(x)
    def __neg__(self):
        return V(-self.x)

def f(a):          # `a` is a variant -- this is the whole bug
    return (-a).x

print(f(V(1.0)))   # CPython: -1.0     pxx: TypeError: expected a number, got object
```

Drop the function and evaluate `-A` at module level against a static `A` and it
is correct, which is why this does not show up in a small test.

## WHERE

`PyUserArithCall1` / `PyVarUserArith` (pylib.pas) are the binary shape --
`(self, other)`, `pk[1] <> 22` gates on a Variant second parameter. The unary
dunders take `(self)` only, so none of that machinery fits them and there is no
one-argument twin. The numeric unary path raises "expected a number, got
object" before any dunder lookup happens.

`~` printing nothing is worse than the other two and should be diagnosed
separately -- a silent death is not the same failure as a raise.

## REACHABILITY IN THE ONE REAL PROGRAM WE HAVE: ONE SITE, AND IT WORKS

Censused by lekkerzeilen-c8, 2026-09-14, over the whole package: 353 non-literal
unary / `abs()` sites. All but one are numeric (`-wind.x`, `abs(self.rudder)`).
Zero `~` on anything. Zero `abs(<object>)` -- math3d declares no `__abs__`, so
those would fail under CPython too.

The single object-operand site is `vessel.py:733`, `Mat4.translation(-offset)`,
where `offset` is a LOCAL assigned from `Vec3(*pivot)`. It runs for every
non-hull fitting of every drawn vessel every frame and does NOT raise -- the
local kept a static class type (star-unpacking does not defeat the inference),
so it takes the compile-time arm.

That is reachability, not correctness: the site never reaches the runtime arm,
which is why it works, and it says nothing about whether the runtime arm is
right. Prio dropped 85 -> 55 on that census.

## NOT FIXED HERE AND WHY

Found while fixing two object-lifetime leaks on the same evening; this is a
DIFFERENT mechanism (dispatch, not refcounting) and wiring a one-argument
dunder caller is its own change. Banked rather than microfixed.
