---
prio: 40
track: N
type: bug
blocked-by: []
---

# A constructor declaring `**kw` still rejects an unmatched keyword

- **Type:** bug (NilPy, **valid CPython refused**) — **Track N**
- **Found:** 2026-08-09, gating
  [[bug-nilpy-keyword-arg-collides-with-a-star-defs-default-filler]]

```python
class K:
    def __init__(self, a, b=2, *rest, **kw):
        self.t = (a, b, rest, sorted(kw.items()))

k = K(1, b=5, z=6)      # CPython fine; pxx:
```

```
error: Nil Python: K has no field or constructor parameter named 'z'
```

`b=5` binds fine. Only the keyword that should fall through to `**kw` is
refused, so the constructor call path is checking keyword names against the
declared fields/parameters WITHOUT the `**kw` escape that the ordinary def path
has (`PyKwArgIndex` returns a NEGATIVE marker for an unmatched keyword when
`ProcPyKwIdx >= 0`, and `PyPackStarArgs` decodes it into the dict).

## Shape of a fix

Find the constructor-call keyword check and give it the same `ProcPyKwIdx`
escape the def path uses, so an unmatched keyword becomes the negative marker
rather than an error. The packing itself already exists and is shared — this is
about which call path reaches it.

Check the METHOD path in the same pass: `PyParseStarMethodArgs` exists for
methods with star parameters, so the method form may already work and only the
constructor may be missing it. Verify rather than assume — `k.m(1, b=5, z=6)`
on the same class is the one-line probe.

## Gate
`.npy` diffed against CPython: a constructor with `**kw` taking matched and
unmatched keywords, the same for a method, and a class WITHOUT `**kw` still
rejecting an unknown keyword (that diagnostic is correct and must stay).

## 2026-08-09 — diagnosed and parked (claude-AN), not started

### The ticket's "check the method path" question: answered

`k.m(1, b=5, z=6)` **works**. Only the constructor refuses. Measured, so the fix
is genuinely one path, not two.

### Why it is not a small change

The constructor call is **separate machinery from the def path**, not a caller
of it. `PyParseCtorCall` (pyparser.inc ~4930) has its own keyword handling:
`kwSlot[]` indexed by FIELD, its own re-emit loop in field order, its own
hole-filling from dataclass defaults and from ctor-parameter defaults, and its
own variant-unboxing arm for a class-typed field. It never calls
`PyPackStarArgs` / `PyBindKwArgs`, which is where the `**kw` escape and the
container packing live.

So this is not "add the ProcPyKwIdx escape" as the shape section guessed — the
escape has nowhere to hand the keyword to. Supporting `**kw` here means either
teaching that path to pack a kwargs dict, or routing the constructor through the
shared def path, which is the better answer and the bigger one.

That path is also dense with hard-won special cases (the tkinter façade hole
filling, the dataclass default nodes, the unbox-with-retain for a class-typed
field, all carrying their own tickets), so it is exactly the code not to rewrite
at the tail of a session.

### Where it sits

Two mechanisms serving one concept — the counting test from
`root-cause-over-microfix` — so the honest fix is the convergence, and it wants
a session that can hold it. Loud failure, workaround is to declare the option as
a real parameter instead of relying on `**kw`.
