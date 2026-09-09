---
slug: bug-n-a-user-method-on-a-parenthesised-receiver-of-unknown-type-is-not-parsed
track: N
prio: 55
type: bug
status: done
owner: ""
created: 2026-09-09
found-by: frankB
tags: [nilpy, classes, expressions, lekkerzeilen]
blocked-by: []
summary: "`(p).norm()` and `(p - q).norm()` fail with `Nil Python: expected newline after statement` when the receiver's static type is UNKNOWN -- an unannotated parameter. Measured 2026-09-09 against compiler/pascal26 57ba8b0c2c8d and confirmed identical on the PINNED binary, so it is not new. The parenthesis is what breaks it: `p.__sub__(q).norm()` and `t = p - q; t.norm()` both compile and give CPython's answer, and annotating the parameter `p: V` makes the parenthesised form compile too. Int/str intrinsics are unaffected because they have their own suffix-ahead check. This is the SECOND blocker on lekkerzeilen's math3d.py and it now blocks the same seven runtime modules the class-body alias bug did, at math3d.py:287."
---

# Repro, with the four controls that locate the boundary

```python
class V:
    def __init__(self, x): self.x = x
    def __sub__(self, o): return V(self.x - o.x)
    def norm(self):       return self.x

def f(p, q):
    return (p - q).norm()      # pascal26: expected newline after statement
print(f(V(3), V(1)))           # CPython: 2
```

| shape | verdict |
| --- | --- |
| `(p - q).norm()`, unannotated params | **error** |
| `(p).norm()`, unannotated — **no operator at all** | **error** |
| `t = p - q` then `t.norm()` | compiles, `2` |
| `p.__sub__(q).norm()` — same call, no parentheses | compiles, `2` |
| `def f(p: V, q: V)` — annotated | compiles, `2` |
| `(a - b).norm()` at MODULE level, `a = V(3)` | compiles, `2` |

**The operator is not the variable and neither is the dunder** — `(p).norm()`
fails on its own. What the failing rows share is a **parenthesised receiver whose
static type the parser does not know**; give it a type by any route (annotation,
module-level binding, a temp) and it works.

# Where it is

`pyparser.inc`, the postfix tail after a parenthesised expression. Its comment
records the sibling fix `bug-nilpy-postfix-after-a-parenthesised-expression`,
which made this tail **stand down** in Python mode and hand `.` and `[` to
ParseFactor's own Python suffix loops, on the stated grounds that those already
cover *"str methods, subscript/slice, variant dispatch, class methods"*. That is
true for a receiver of known type and for the int/str intrinsics — `("ab").upper()`
and `(1 + 2).bit_length()` both work, and the tail exempts the int ones explicitly
via `PyIsIntMethodSuffixAhead`. **The variant-receiver arm is the hole**: the
grouped value is left with the `.` dangling, the statement parser sees a token it
did not expect, and reports the newline error.

**A COMMENT AND THE CODE DISAGREE HERE, WHICH IS ITS OWN FINDING** — the comment
claims the handoff covers variant dispatch and it does not, so whoever fixes this
should decide which is wrong before editing either. Matching the comment to the
behaviour would destroy the evidence.

# Why it ranks here

It is the residual of `bug-n-a-class-body-cannot-alias-a-method-defined-above-it`
and inherits its blast radius exactly: with that one fixed, `math3d.py` now
reaches line 287 (`f = (target - eye).normalized()` inside `Mat4.look_at`) and
stops there, so the same seven modules — math3d, wind, rig, vessel, sim, traffic,
app — are still blocked, on one line again.

**Fork: fix nilpy, not the source.** `(a - b).method()` is ordinary Python and
the umbrella's cheat licence is for constructs that are *principally*
incompatible; this is a parser gap with a one-line workaround that would have to
be applied wherever it recurs.

**Not new, and that is measured, not assumed.** The pinned compiler — which
predates the alias fix entirely — gives the identical error on the identical
line once the alias line is deleted, so nothing here was introduced by that
change. It was masked behind the earlier error.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
