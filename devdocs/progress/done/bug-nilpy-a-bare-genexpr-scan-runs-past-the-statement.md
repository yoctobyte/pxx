---
track: N
prio: 60
type: bug
blocked-by: []
resolved: 9821c16fa
summary: "PyBareGenExprAhead scanned forward with no statement boundary, so `p.extra = 7` followed several lines later by an unrelated `for` loop parsed the 7 as a generator expression over it — reported as \"undefined variable\" on the LOOP's own iterable, in a function whose parameter plainly exists. A regression from c003256c0; test_nilpy_getattr_computed_name was red."
---

# The bare-genexpr lookahead ran past the end of the statement

```python
class P:
    def __init__(self, n):
        self.n = n

p = P(3)
p.extra = 7            # <- the value is parsed through ParseArgExpr

def to_dict(o, names):
    out = {}
    for nm in names:               # pascal26: error: undefined variable (names)
        out[nm] = getattr(o, nm)
    return out
```

Found 2026-08-15 while checking neighbours after an unrelated property fix:
`test/test_nilpy_getattr_computed_name.npy` — a WIRED suite test — no longer
compiled.

## Root cause

`c003256c0` moved the bare-generator-expression diversion into `ParseArgExpr`,
which is right: it is the one routine every call argument passes through. But
its lookahead, `PyBareGenExprAhead`, only stopped at a comma or a closing
bracket at depth 0 — never at a statement boundary.

A dynamic attribute STORE parses its value through `ParseArgExpr` too, and that
value is not inside any brackets. So the scan left the statement, walked over
the newline, and found the `for` of an unrelated loop several lines below;
`7` was then parsed as a generator expression over it.

**The diagnostic pointed at the loop, not the store** — "undefined variable
(names)" on a parameter that plainly exists — which is why it read as a
scoping bug in a function forty lines away from the cause. Bisected instead of
reasoned about: `d9d3f39f1` clean, `c003256c0` red, and the trigger line found
by compiling growing prefixes of the test.

## The fix

The scan stops at `tkNewline` / `tkIndent` / `tkDedent` / `;` / `:` at depth 0.
A genexpr argument always sits inside the call's parentheses, and NilPy
suppresses newlines inside brackets, so a newline at depth 0 means the scan has
left the argument list entirely.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v336.
`test_nilpy_getattr_computed_name` compiles and matches again; the eight
neighbouring genexpr/comprehension/format tests re-checked against their
oracles.

Worth keeping: this is the second lookahead-shaped defect in two days
(`PyStarArgAhead`'s siblings were the first). A token scan that answers "is
construct X ahead" needs a stop condition for the END of the region it is
allowed to look at, and "a bracket or a comma" is not one when the caller may
be outside brackets entirely.
