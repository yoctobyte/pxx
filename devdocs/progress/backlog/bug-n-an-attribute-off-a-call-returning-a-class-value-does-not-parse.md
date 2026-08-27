---
track: N
prio: 58
type: bug
owner: unassigned
blocked-by: []
summary: "`P(7).mk().a` is `unexpected token` — not a wrong value, a PARSE error — when `mk` returns a class-reference construction (`cls(...)` / `self.__class__(...)`) AND the class has a subclass. Without the subclass the identical file compiles. The subclass is what makes the name resolve to a set, and the representative's return type is what the selector arm reads."
---

# An attribute off a call returning a class VALUE does not parse when a subclass exists

```python
class P:
    def __init__(self, a):
        self.a = a
    def mk(self):
        cls = P
        return cls(self.a)      # a classref VALUE call -> variant

class Q(P):                     # <-- delete these two lines and it compiles
    pass

print(P(7).mk().a)              # CPython: 7    pxx: pascal26:11: error: unexpected token
```

```
Expected: ), but got:  (Kind: 81, Line: 11)
pascal26:11: error: unexpected token
  near:    mk   >>>  a
```

## PRE-EXISTING

Measured identical on `stable_linux_amd64/default/pinned` (v384) and on the
fixedpoint carrying [[bug-n-self-class-cannot-be-called-as-a-constructor]],
2026-08-27. Filed from that ticket's sibling sweep, where `self.__class__(...)`
made the shape easy to reach — but it is not that ticket's doing, and the repro
above deliberately uses `cls = P` so it needs no `__class__` at all.

## The boundary, measured

Varying one thing at a time (the failing selector is `.a`, an ordinary field —
`__class__` behaves no differently, which is what rules the dunder out):

| method returns | subclass? | `P(7).mk().a` |
| --- | --- | --- |
| `P(self.a)` — a static ctor | yes | **ok** |
| `cls(self.a)` — a classref value | no | **ok** |
| `cls(self.a)` — a classref value | yes | **unexpected token** |
| `self.__class__(self.a)` | no | **ok** |
| `self.__class__(self.a)` | yes | **unexpected token** |

So it needs BOTH a variant-typed (classref-constructed) return AND a same-named
method set. Neither alone does it.

## Where to look

Not the classref lowering — that is fine in every row above; the value it
produces is correct and `x = P(7).mk()` then `x.a` on a separate line works.
It is the SELECTOR arm after a call: `.` + ident off a call result is claimed
either by the static-class arm (`tk = tyClass`) or by the variant-receiver arm
(pyparser.inc, the `(tk = tyVariant) and (CurTok.Kind = tkDot)` test around the
`bug-nilpy-attribute-off-a-subscript-of-a-call-result-yields-the-variant-tag`
comment). With a subclass present the call's `tk` is evidently neither, so
nothing claims the `.` and the expression simply ends.

`FindProc` returns the *representative* of a same-named set and its `RetType` is
what type inference reads — the hazard called out at length in
[[bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it]]. A subclass is
what turns `mk` into a set of two, so the representative's `RetType` is the
first suspect. **Measure it — `PXXDBG=n.procs` and `a.ast:`** — rather than
assuming; this is exactly the block whose own comments record having broken
self-host and `sum(range(i))` before, and a wrong root cause recorded here is
worth more than the bug.

## Why it matters

A parse error is the good failure mode — nothing silently wrong ships. But the
shape is ordinary: a factory method plus a subclass is the reason to write a
factory method at all, and the diagnostic (`unexpected token` at the field name)
names neither the class-value return nor the subclass, so it reads as a typo.
