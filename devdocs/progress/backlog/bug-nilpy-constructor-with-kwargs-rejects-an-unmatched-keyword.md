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

## Recon 2026-08-09 — the method half is fine, and the suggested fix is not small

### Verified, as the ticket asked, rather than assumed

```python
class K:
    def __init__(self, a): ...
    def m(self, a, b=2, **kw): return sorted(kw.items())
def f(a, b=2, **kw): return sorted(kw.items())

k.m(1, b=5, z=6)   ->  1|5|[('z', 6)]   CORRECT
f(1, b=5, z=6)     ->  1|5|[('z', 6)]   CORRECT
```

**Only the CONSTRUCTOR path is broken.** The method path (`PyParseStarMethodArgs`)
and the plain def path both already route an unmatched keyword into the dict.
So this is one call path missing an escape the other two have — which is what the
ticket suspected, and it is now measured.

### Why "give it the same ProcPyKwIdx escape" is not a two-line change

`PyKwArgIndex` and `PyPackStarArgs` communicate through a MARKER ENCODING on the
argument nodes: `ASTIVal[argNode]` is `0` for a positional, `i+1` for a keyword
that matched parameter `i`, and **negative** `-(keyNode+1)` for an unmatched
keyword, with the key's `AN_STR_LIT` index packed into it. `PyPackStarArgs` walks
the chain and reads exactly that.

The constructor path (`pyparser.inc` ~5137-5300) does not use that encoding at
all. It collects arguments into `kwSlot[fieldIndex]` and then **re-emits the
whole chain in FIELD order**, filling interior holes from `@dataclass` defaults
or from the ctor parameter's declared default. `ASTIVal` on those nodes is never
a keyword marker. So handing the chain to `PyPackStarArgs` cannot work as-is:
the two halves disagree about what the argument nodes mean.

Two routes, neither of them one line:

1. **Teach the ctor path the marker encoding** — put unmatched keywords outside
   `kwSlot`, tag them `-(key+1)`, append them after the field-order re-emission,
   then call `PyPackStarArgs`. Contained, but it interleaves with the hole-filling
   logic, which is the part that makes tkinter-style façades work
   (`tk.Canvas(self, highlightthickness=0)` skipping `width`), so it is exactly
   the code where a regression would be quiet and widespread.
2. **Route a ctor that declares `**kw` through the METHOD path instead**, which
   already works. A class with `**kw` in `__init__` necessarily HAS a ctor
   method, so the `@dataclass` branch (the reason the field-slot re-emitter
   exists) cannot apply to it — the two are mutually exclusive by construction.
   This looks like the smaller and safer change and is probably the one to try
   first, but it needs the construction/`create` split at the end of that
   function read carefully before committing to it.

### Severity note

Loud (a compile error), so nothing computes a wrong answer — which is why this
was parked rather than half-built. The hole-filling code it must not disturb is
load-bearing for every façade in the corpus, and a quiet regression there would
cost far more than the shape this fixes.
