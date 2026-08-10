---
track: N
prio: 55
type: bug
blocked-by: []   # decided 2026-08-08: option B
summary: "`a == b` skips __eq__ and compares identity as soon as ONE operand is a variant (a container element, a for-in variable). Both-static works, so the dunder LOOKS wired up; `a == xs[0]` is silently False."
status: done
owner: claude-AN
---

# `__eq__` is skipped as soon as one operand is a variant

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-04, sizing
  [[bug-nilpy-in-over-objects-ignores-eq]]. It **corrects that ticket's
  premise**, which says "`==` itself now dispatches `__eq__`". It does — but
  only when BOTH operands are statically class-typed.

## Measured (self-hosted binary at HEAD)

```python
class V:
    def __init__(self, v: int):
        self.v = v
    def __eq__(self, o) -> bool:
        return self.v == o.v

a = V(1)
b = V(1)
print(a == b)         # True   correct

xs = [V(1)]
e = xs[0]             # e is a VARIANT
print(a == e)         # False  CPython: True
print(a == xs[0])     # False  CPython: True
for q in xs:
    print(a == q)     # False  CPython: True
```

Identical class, identical field, and `a == b` is True while `a == xs[0]` is
False. No diagnostic.

## Why it matters more than the `in` ticket it came from

A container element and a for-in variable are variants, and those are where
objects normally live in Python. So the dunder works in exactly the shape a
minimal test uses (two named locals) and fails in the shape real code uses.
That is also why it went unnoticed while `__eq__` was being wired up.

It is the same cause as the `in` ticket — `__eq__` dispatch resolves against
the operand's STATIC class (parser.inc's comparison arm), and a variant has
none, so the compare falls back to pylib's `PyVarEq`, which compares object
slots by pointer.

## This is what blocks the cheap fix for `in`

Rewriting `x in xs` into a loop over `x == xs[i]` — the obvious frontend-only
fix, needing no runtime hook — **cannot work**, because `x == xs[i]` is exactly
the expression measured False above. Both tickets therefore need the same thing:
a way for `PyVarEq` to reach a user `__eq__` at RUN time. Fixing that fixes `==`,
`in`, `list.count/index/remove` and object dict keys together.

## Fix shape (recon, not started)

`__pxxMethodAddress(Instance, Name)` in `compiler/builtin/builtin.pas` already
walks a class's RTTI method table by name at run time, which is the lookup half.
Two things need checking before building on it:

1. whether a NilPy method carries the `PXX_RTTI_METH_PUBLISHED` flag — that
   routine skips anything that does not, and it is a filter over a table with
   three stride consumers ([[project_rtti_method_table_multi_consumer_stride_landmine]]);
2. the **ABI**, which is the real risk: `__eq__(self, o)`'s second parameter is a
   variant when unannotated and a class pointer when annotated `o: V`, so calling
   the found address through one fixed signature would miscompile half the cases
   — precisely the shape blindspot
   [[project_string_conversion_shape_blindspot_pattern]] describes.

The safe shape is therefore a compiler-emitted **wrapper** of fixed signature
(`function(a, b: TObject): Boolean`) per class that declares `__eq__`, published
under a fixed name that `PyVarEq` looks up — so the marshalling stays where the
types are known and the runtime call has one ABI.

## Gate

A `.npy` diffed against CPython: `==` and `!=` with each operand in turn a
variant (subscript, for-in variable, `.get()` result, function argument); a class
WITHOUT `__eq__` still comparing by identity; `__eq__` annotated `o: V` and
unannotated, both dispatching; and the `in`/`count`/`index`/dict-key consumers
from [[bug-nilpy-in-over-objects-ignores-eq]].


## 2026-08-04 (later) — feasibility probed; it is a FEATURE, not a bugfix

Went at the runtime hook and stopped at the point where it stops being a fix and
becomes compiler work. Three things measured, so the next session does not
re-probe them:

1. **A NilPy method is NOT published in RTTI.** `AddUMethod` sets
   `UMthPub := 0` (`parser.inc`), and the RTTI emitter only sets
   `RTTI_METH_FLAG_PUBLISHED` when `UMthPub = 1`. `__pxxMethodAddress` skips
   every unpublished entry, so it cannot see `__eq__` today even though the
   method table itself holds every method. Publishing dunders specifically would
   be the narrow way in — not publishing everything.
2. **`__pxxMethodAddress` is not reachable from ordinary source** — "undefined
   variable" from a plain program. It lives in `builtin.pas`; whether `pylib`
   may call it is the next thing to check, and it decides whether the lookup can
   live in `PyVarEq` at all.
3. **A method's code ADDRESS is not expressible**: `@TC.eq` gives "cannot call
   non-static method on class type directly". So the cheaper design that avoids
   RTTI — a registry filled at module init with
   `pyeq_register(<class>, @<method>, <param-kind>)`, letting `PyVarEq` pick
   between a variant-taking and an object-taking call shape by a registered flag
   instead of needing a synthesized wrapper — **cannot be written in source
   either**. The frontend would have to emit the address node itself.

So both routes need compiler-side work (publish dunders in RTTI, or emit a
method-address + registration at module init), plus the `PyVarEq` call. That is
a feature-sized Track A+N change with an ABI in the middle, not something to
half-build unattended — the same call the closure-leak ticket's two prior
sessions made about adjacent work.

The design recorded above still looks right; what this adds is that the
`param-kind flag instead of a wrapper` simplification is available and removes
the synthesized-wrapper half, IF the frontend can emit the address. Returned to
`backlog/` with that.


## 2026-08-07 — marked BLOCKED, not merely feature-sized

Picked up as the top-ranked ready N bug and put straight back down: the 08-04
probe above concludes the fix needs a run-time route from `PyVarEq` to a user
`__eq__`, and *which* route — reflective RTTI lookup, a per-class dunder table,
or compile-time guarded dispatch — is exactly the fork
[[decide-nilpy-runtime-dunder-dispatch-strategy]] holds, which the user has
**postponed twice** ("postpone, i need to study this", 2026-08-03) as reserved
judgement rather than missing information.

Building an `__eq__`-only hook now would answer that question by accident, in
the one shape that is hardest to unpick later — a private path for one dunder is
the thing the decision exists to prevent. So: `blocked-by` the decision, which
also stops it surfacing at the head of the ready queue every session and being
re-probed. Nothing here is stale; resume from the fix shape above the moment the
strategy lands.

## Unblocked 2026-08-10 — the postponed decision has landed

[[decide-nilpy-runtime-dunder-dispatch-strategy]] is in `decided/`: **option B**,
a compile-time-generated switch on class identity, degrading only when
`PyDynAttrEverAssigned` says the class is dirty. This ticket's own closing line
was *"resume from the fix shape above the moment the strategy lands"* — it has.

What that changes: the reason this was blocked was that building an `__eq__`-only
hook would have answered the strategy question by accident, in the shape hardest
to unpick later. That risk is gone — the answer is now on record, so a fix here
just has to be the option-B shape rather than a private path for one dunder.

Honest about what is still true: option B's dispatcher does not exist yet, and
the decision parks the broad build to rainy-day. The cheaper neighbour
[[bug-nilpy-dunders-not-dispatched-through-containers]] is a HOOK into dispatch
that already works and the decision names it the piece to take first — expect to
want that one before this one.

Also cleared here: `status: working` / `owner: claude-A-N`, a stale lock on a
ticket that has sat in `blocked/` since 2026-08-03.

## 2026-08-10 — narrower than it reads: membership already dispatches

Measured while closing [[bug-nilpy-in-over-objects-ignores-eq]]. That ticket and
this one both assert the two share one `PyVarEq` bottleneck and need one fix.
**They no longer do:**

```python
a = V(1); xs = [V(1)]
a in xs        -> True   (CPython True)   __eq__ VERIFIED to run
xs.count(a)    -> 1      (CPython 1)      __eq__ VERIFIED to run
xs.index(a)    -> 0      (CPython 0)
ys.remove(V(1))-> [2]    (CPython [2])
a == xs[0]     -> False  (CPython True)   <-- THIS ticket, still broken
```

A `print` inside the dunder confirms it actually runs for the membership family
and never runs for `==`. Identical on `pinned`, so it predates today.

So the remaining defect is **only the `==` operator against a variant operand**,
not the whole equality surface. Two consequences for whoever picks this up:

- the "fix `PyVarEq` and everything follows" framing is out of date — something
  already reaches `__eq__` from the container side, so the useful first question
  is *what route membership uses*, and whether `==` can be pointed at the same
  one instead of building a second;
- the sibling's `blocked-by` edge on this ticket was dropped when it closed, so
  this one no longer blocks anything and ranks on its own priority.

The user-visible shape is unchanged and still the reason this matters: the
dunder works with two named locals and fails the moment one side is a container
element, which is the shape real code writes.

No code changed.

## Resolution (2026-08-10)

The 08-10 note above asked the right question — *"what route does membership
use, and can `==` be pointed at the same one instead of building a second"* —
and the answer is yes, in about twenty lines. But **the first cut put it in the
wrong place, and that is the part worth recording.**

### Cause, confirmed

Every dunder arm in `parser.inc`'s comparison block is guarded on
`IntToTypeKind(ASTTk[left]) = tyClass` **and** the same for the right. A variant
has no static class, so `a == xs[0]` matched none of them and fell through to
the generic variant compare — `IR_VAR_BINOP`, which compares tag and payload and
knows nothing about user classes.

Two equalities for one concept, and the one the `==` operator used was the one
that could not see a dunder: `PyVarEq` in pylib is a complete Python `==`
(int-family cross-tag, int-vs-float, strings and containers by content, and
`PyUserObjEq` for a user `__eq__`) and was reachable only from container methods.

### The wrong place, and how it was caught

The first cut added a fourth compile-time arm in `parser.inc` that diverted
variant-vs-variant comparisons to a pylib router. Every repro passed — the
ticket's cases, `!=`, annotated and unannotated dunders, identity fallback,
scalars and containers through variants, `== None` — and `tools/gate.sh quick`
was **GREEN**.

`make test-nilpy` was not. `test_nilpy_int_promotion_default` failed on one
line: `2**64 == 2**64` had become **False**.

`PXXDBG=a.ir` on the old compiler shows why, and shows it in one dump: the
variant comparison was never a bare `IR_VAR_BINOP`. It is a **try-chain** —
`PXXPromoVarCmpTry(left, right, op)` answers 0 = not handled / 1 = False /
2 = True, and only its "not handled" branch reaches `IR_VAR_BINOP`. The new arm
sat in front of the whole chain and stole the promotable-int family with it.

That is [[project_nilpy_static_vs_variant_operand_paths_diverge]]'s shape from
the other side, and the lesson is the one
`feedback_widening_a_lowering_needs_a_family_sweep_not_a_wider_gate` records:
moving a lowering to a different path silently drops what the old path enforced,
outputs matched, and quick was green.

### Where it actually belongs

`ir.inc`'s `IRPyVarEqFallback` — the **fallback arm of that existing chain**, not
a rival to it. The promo try still runs first and answers first; only when it
says "not handled" does `==` / `!=` go to pylib's `pyvar_eqv` (`PyVarEq` by
another name, taking the two variant slots by address exactly as
`PXXPromoVarCmpTry` takes them). Ordering operators keep `IR_VAR_BINOP`
untouched, and `!=` is the negation.

So the final change is: **one link of an existing chain re-pointed**, plus a name
in pylib's interface. No new arm, no second equality.

### Four misses, one mistake, and the shape that ends it

With the fix in the right *place*, `make test-nilpy` failed three more times,
each on something the change had no business touching:

| run | what broke | why |
| --- | --- | --- |
| 2 | `dst is not src` over variant params | `is` lowers to the SAME tkEq node and is told apart only by `PY_BINOP_IDENTITY` — the marker the by-contents arms already consult, and the new one did not |
| 3 | `expr[j] == " "` (a tokeniser loop) | `PyVarEq` wants equal tags outside the numeric family, so CHAR vs one-character STRING went False |
| 4 | `0 == None` → True | **`IR_VAR_BINOP` is not a routine.** On x86-64 it is INLINE-emitted code (`EmitVarBinOp`) with its own None arm, char/string arms and numeric double-dispatch; builtinheap's `PXXVarBinOp` is a DIFFERENT implementation for the other backends. Calling the latter dropped the former's None arm |

All four are one mistake: **replacing a fallback instead of adding a link in
front of it.** Each fix widened my model of what the old path did and the model
was still wrong the next run.

The shape that ends it is the one `PXXPromoVarCmpTry` was already using, one
link up the same chain: a **TRY** answering `0 = not handled / 1 = False /
2 = True`. `pyvar_eqv` handles exactly one case — an OBJECT (tag 7) on either
side — and declines everything else, so every non-object comparison emits
byte-for-byte the instruction it emitted before. A try that declines cannot
regress a case it never sees; a replacement has to enumerate them, and four runs
proved I could not.

`is` declines through the same door (the `PY_BINOP_IDENTITY` check sits in the
try's guard, not in a separate arm).

### The sibling it exposed

With `==` routing through `PyVarEq`, `b"ab" == b"ab"` was still False — that
routine had content arms for `TPyList` and `TPyDict` and **none for
`TPyBytes`**, though `pybytes_eq` had existed all along. One line, found by the
sibling-of-a-double-case check the moment the operator started arriving there
(`devdocs/dev/normalise-dont-special-case.md`). Fixed here rather than filed:
it is the same routine, the same concept, and leaving it would have meant
shipping a route that is right for two of three containers.

### Measured, all against CPython

Before: `a == b` True, `a == xs[0]` False, `xs[0] == a` False,
`xs[0] == ys[0]` False, for-in False, `a != xs[0]` True.
After: every one matches CPython.

`test/test_nilpy_eq_dunder_variant_operand.npy` (`.expected` generated by
CPython), wired into `make test-nilpy`: subscript / for-in / dict-get /
function-argument operands in both orders, `!=`, an ANNOTATED `other` parameter
beside an unannotated one, a class WITHOUT `__eq__` keeping identity comparison,
the membership family this route came from, and three regression blocks that
exist because of the above — **bytes** by content, **promotable ints**, **`is` / `is not`** over variant
parameters, and **char-vs-string** — the last three because cuts one, two and
three broke exactly them.

Gate: `tools/gate.sh quick` GREEN + `make test-nilpy` green.

### What this closes and what it does not

Closes the last item on the equality surface: the 08-10 measurement showed
membership, `count`, `index` and `remove` already dispatched and `==` did not.
It does NOT build option B's general dispatcher — it did not need to, because
the run-time route already existed and only had to be reached. The broad build
stays where [[decide-nilpy-runtime-dunder-dispatch-strategy]] parked it.

Found while gating, filed not fixed:
[[bug-nilpy-a-user-hash-dunder-is-ignored-for-dict-keys]] — a class defining BOTH
`__hash__` and `__eq__` is stored under a key the dict then cannot find, while
`k1 == k2` answers True right beside it. Pre-existing at `pinned`.

## Log
- 2026-08-11 — resolved, commit PENDING-COMMIT.
