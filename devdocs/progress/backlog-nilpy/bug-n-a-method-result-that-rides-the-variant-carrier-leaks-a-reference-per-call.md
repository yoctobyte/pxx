---
type: bug
track: N
prio: 85
status: open
slug: bug-n-a-method-result-that-rides-the-variant-carrier-leaks-a-reference-per-call
---

# A method result that rides the VARIANT carrier leaks a reference on EVERY call

`return self.q` leaks +1 refcount per call. So does `return self.a.b`,
`return self.rows[0]` and `return self.lines[a:b]`. `return self` and
`return Q()` are clean. **The discriminator is the CARRIER, and it is visible in
one field of the AST.**

This is NOT the discarded-result bug
(`bug-n-a-freshly-allocated-value-whose-result-is-discarded-is-never-released`).
It leaks when the result is BOUND, which is the common spelling — binding is
what made that other ticket's `me_bound` row clean, and it does not rescue this
one.

Measured 2026-09-15, compiler `f5c08154dcac1f53`, CPython 0 on every row.

## THE CARRIER IS THE WHOLE STORY

`PXXDBG=a.ast` on six getter calls, reading the result type tag off the
`AN_VIRTUAL_CALL` node (`tk`):

| method | returns | `tk` | | leaks |
|---|---|---|---|---|
| `g_obj` | `self.q` | **22** `tyVariant` | | **yes** |
| `g_chain` | `self.mid.leaf` | **22** | | **yes** |
| `g_index` | `self.rows[0]` | **22** | | **yes** |
| `g_slice` | `self.lines[1:3]` | **22** | | **yes** |
| `g_self` | `self` | 6 `tyClass` | | no |
| `g_fresh` | `Q()` | 6 `tyClass` | | no |

An attribute read, a chained attribute read, an index and a slice all come back
through the VARIANT carrier. `self` and a constructor result do not. **Every
variant-carried row leaks and no tyClass row does.**

## objtrace, ONE CALL PER SHAPE, NET OF THE REBIND RELEASE

| shape | retains | releases | net |
|---|---|---|---|
| `return self.q` | 2 | 1 | **+1** |
| `return self.mid.leaf` | 2 | 1 | **+1** |
| `return self.rows[0]` | 3 | 2 | **+1** |
| `return self.lines[1:3]` | 1 alloc + 1 retain | 1 | **+1, ends at rc=1** |
| `return self` | 1 | 1 | 0 |
| `return Q()` | 1 alloc | 1 | 0 |

Depth and indexing change the retain COUNT and never the net. A DIRECT attribute
read at the call site (`k = h.q`) emits exactly ONE retain and is clean — so the
attribute read itself is correct and it is the method RETURN path that adds the
second one. The consumer is retaining a result that already arrives owned, in a
frontend whose stated invariant (ir.inc, the argument-spill comment) is *"all
NilPy results are owned + the consumer borrows"*.

## SCALARS ARE FREE, AND THAT MATTERS FOR RANKING

`return self.level` (float), and the same for int and bool, shows **no object
traffic at all** in objtrace and 0 bytes/call. A variant-boxed scalar allocates
nothing and retains nothing. So only the object-returning accessors are in
scope.

## RSS IS BLIND TO THIS WHENEVER THE RECEIVER OUTLIVES THE LOOP -- READ THIS BEFORE QUOTING A ZERO

The first measurement taken here used a module-level `h` built once and reported
`return self.q` at **0 bytes/call**, i.e. "clean". That is wrong. objtrace on the
same program, five calls:

```
rc 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 ...
```

Two retains and one release per call, forever; the object can never be freed. A
leaked REFERENCE allocates nothing, so RSS only shows BYTES when the referent is
fresh per iteration. **A 0 in an RSS column does not retire a row here** — this
is the third time this family has produced a confident wrong "clean" from an RSS
table, and the ticket above records the other two.

The slice row is the exception and the expensive one: it allocates a fresh
backing buffer per call, so it IS RSS-visible at **200 bytes/call**.

## REPRO

`devdocs/progress/repro-n-a-variant-carried-method-result-leaks.npy`

## WHY 85

Getters are ubiquitous and this needs no unusual spelling — no discard, no
conditional, just `return self.something` consumed normally. Found while
answering a lekkerzeilen census: 27 `return self.<attr>` sites across 21 methods
in that package, plus a wide family of `@property` accessors returning
`self.a.b` that the narrow grep missed. `Vessel.state` is read inside a physics
step running at 120 Hz, and `Tab.shown` returns a SLICE per visible panel per
frame — the 200 b/call row.

## WHERE TO LOOK

The return lowering for a method whose result type is `tyVariant`. `return self`
and `return Q()` take the `tyClass` path and are correct, so the two paths can
be diffed directly rather than reasoned about. Settle with objtrace whether the
fix belongs at the RETURN (stop retaining a value that is already owned) or at
the CALL SITE (stop retaining a variant-carried result), and mind that the
direct attribute read at a call site must keep its single retain — it is the
balanced case and the fixture carries it as the control.
