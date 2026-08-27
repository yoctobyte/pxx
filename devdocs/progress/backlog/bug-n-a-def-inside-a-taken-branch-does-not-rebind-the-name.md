---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`def g(): return 1` followed by `if True: def g(): return 2` still calls the FIRST g. Split out of bug-n-a-module-level-rebinding-still-loses-to-a-def-of-the-same-name when that one was fixed: it is a different mechanism — the def side, not the assignment side. A nested def has a position, but PyRegisterDefShells only walks module-level defs at DEPTH 0, so a def inside a branch never gets one."
---

# A `def` inside a taken branch does not rebind the name

```python
def g():
    return 1
if True:
    def g():
        return 2
print(g())           # CPython 2, pxx 1
```

Measured at `e8b72f8afeb6` (the fixedpoint carrying the module-rebinding fix)
and unchanged by it.

## Why it is a different mechanism from the ticket it was split from

[[bug-n-a-module-level-rebinding-still-loses-to-a-def-of-the-same-name]] was the
**assignment** side of "which binding ran last" having no position. This is the
**def** side, and a def does have `ProcPyDefTok` — so the comparison would work
if the position existed.

It does not, because `PyRegisterDefShells` walks module-level defs at **depth 0**
only, and that restriction is load-bearing rather than incidental: its own
comment says registering unconditionally "is safe HERE and only here" precisely
because the pass visits each module-level def token exactly once. A def inside
an `if` suite is at depth 1, is never visited, and so never gets a shell, a
`ProcPyDefTok`, or a place in the ordering.

## Shape of the fix

The obvious move — walk deeper — has to answer what the depth-0 restriction is
protecting: a def inside a `class` suite is a METHOD and must not become a
module-level name, and a def inside another def is a nested def with its own
machinery. So "depth > 0" is not one case but at least three, and only the
`if` / `try` / `while` / `for` suites are module-level bindings that happen to be
conditional.

Note the asymmetry with the assignment side, which is deliberate and correct
there: `PyDefRebindTok` counts only depth-0 assignments, because a conditional
assignment must NOT displace a def (a `f = ...` under a branch that never runs is
legal CPython, and NilPy is upward compatible). A conditional **def** is the same
shape and would want the same answer — which suggests the honest fix may be that
both sides stay depth-0 and this ticket is closed as "conditional bindings are
not tracked, by design, in both directions". That is a Track U question if the
implementer disagrees rather than something to settle in passing.

## Gate

`g()` answers 2, and the `if False:` counterpart still answers 1.
