---
track: U
prio: 40
type: decision
summary: "DECIDED 2026-08-08: multiple inheritance is FLATTENED at compile time. The first base with no body in this file (or the first base) is the real parent; every other base's own body is replayed into the derived class, never its ancestors. Divergences from CPython: isinstance/except do not see a flattened base unless its class is recorded as one at run time, super() across a flattened body is refused, and a diamond is refused where flattening could drop or duplicate an ancestor. A diamond whose flattened mixins have every ancestor in the real parent chain drops and duplicates nothing, and the exception idiom `class E(LocalError, FileNotFoundError)` is that shape."
---

# Decide: multiple inheritance — C3, delegate, or leave refused?

Escalated 2026-08-07 from
[[bug-nilpy-multiple-inheritance-does-not-parse]], whose cheap half (a
diagnostic naming the constraint instead of "unexpected token") already landed.
What is left is not a bug fix, it is a design choice, so it should not be made
by whoever happens to pick the ticket up.

## The fork

The underlying Pascal object model is **single-inheritance**, so a second base
cannot be a real parent. Three options, from that ticket:

1. **Full C3 linearisation.** Flatten the MRO at compile time and resolve each
   attribute to the winning definition. Correct for the diamond
   (`D(B, C)` with both deriving from `A` must resolve D, B, C, A), and the most
   work.
2. **Second base as a delegate.** Real inheritance from the first base;
   attributes not found there forward to an embedded instance of the second.
   Handles the mixin idiom, which is what most real code uses it for. Gets the
   diamond wrong exactly where C3 would pick C over an inherited-from-A member
   of B.
3. **Stay refused.** Today's behaviour: a clear diagnostic telling the reader to
   use single inheritance or compose.

## What is NOT in question

Silently accepting the comma and ignoring the second base is ruled out by the
ticket already — it turns a compile error into a wrong method being called at
run time.

## Why it needs you

The trade is between **coverage of real Python** (mixins are common; option 2
buys most of it cheaply) and **not shipping a subtly wrong MRO** (option 2 is
observably wrong in the diamond, which is exactly where someone would trust it).
Option 3 is honest and free but keeps blocking corpus work.

This is a *how much Python do we mean to be* question, which is the sort
`devdocs/dev/nilpy-semantics-divergences.md` says belongs to you, not a lane
agent picking the reachable option.

## Recommendation

**Option 2 (delegate) with the diamond REFUSED.** Take the mixin case, which is
the one real code needs, and keep the compile error for the shape where the
delegate model would be wrong (two bases sharing an ancestor). That yields no
silently wrong answers, unblocks the common idiom, and leaves a clean upgrade
path to C3 later — the refusal becomes dead code rather than something to undo.

Unblocks: [[bug-nilpy-multiple-inheritance-does-not-parse]].

## DECIDED 2026-08-08 (user): FLATTEN at compile time

> flattening sounds sane

`class D(B, C):` is accepted by **copying C's methods into D**, compiled with
`self` = `D`, with conflicts resolved in **C3 left-to-right order** (B wins over
C). No delegation, no runtime dispatch, no reflective lookup — the observable
behaviour of C3 produced entirely at compile time, which is the compiler-shaped
answer.

### The delegate option is WITHDRAWN, and why matters

The earlier recommendation on this ticket was delegate-with-the-diamond-refused.
That was wrong and is retracted: **delegation breaks the main mixin idiom**,
because in Python a mixin's `self` IS the derived object.

```python
class ReprMixin:
    def __repr__(self):
        return f"{type(self).__name__}({self.value})"   # self.value lives on D
```

With an embedded `C` instance, `self` is the mixin and `self.value` does not
exist. Reaching back into the derived object is *why* mixins exist, so
delegation handles only the mixins that need nothing from their host. Flattening
gets this right by construction — the body is compiled against `D`.

### The interface idea: right instinct, and RTTI already supports it

Asked whether the second base could be treated as an interface. As a shortcut it
does not pay — an interface is a contract with **no bodies**, while a mixin is
bodies with no state, so it supplies the type and none of the code. But as a
*second layer* for IDENTITY it is exactly right, and the runtime side already
exists:

- `PXX_RTTI_PARENT = 8` — RTTI models a **single** parent pointer. No MRO, no
  second base. Flattening keeps that chain honest.
- RTTI also carries a per-class **interface table**: one 24-byte entry per
  implemented interface (GUID inline + a pointer to that `(class, interface)`
  IMT), and *every* implemented interface gets an entry, with `GetInterface`
  walking the parent chain. So **"one parent + N interfaces" is already
  modelled**.

What is missing is only frontend-side: NilPy never creates an interface
(`UClsIsInterface` has ZERO references in `pyparser.inc`) and `isinstance` walks
the parent chain via `IsSubclassOf` without consulting the interface table.

### Correctness — the known divergences from CPython

CPython marks this with `__bases__` (direct bases) and `__mro__` (the C3
linearisation); `isinstance`/`issubclass` walk `tp_mro`, attribute lookup walks
`__mro__`, and `super()` uses `__mro__` **plus the current class's position**.

Flattening is correct for **method resolution and state** on a non-diamond
mixin, and diverges here — all of it detectable at COMPILE time, which satisfies
the standing detect-and-halt-or-diagnose rule:

1. **`isinstance(d, C)` / `issubclass(D, C)` answer False** (CPython: True).
   *The* divergence, and precisely what the later interface layer fixes.
2. **`super()` cooperative chains break.** On a `D(B, C)`, CPython sends
   `B.__init__`'s `super().__init__()` to **C**; a flattened body goes to B's own
   base. `super().__init__(**kwargs)` chaining is idiomatic in mixin-heavy code,
   so this needs a **diagnostic**, not silence.
3. `type(d).__bases__` / `__mro__` introspection answers wrong.
4. Conflict order must follow C3 left-to-right — implementable exactly, but must
   not be left to accident.
5. **Diamond with state**: C3 gives ONE shared `A`; naive flattening can give
   two. This is the concrete reason the diamond is refused in v1.
6. Class-level attributes on the mixin must be copied too, and that lands on the
   class-attribute lowering (shared slot vs copy-at-construction) reworked
   2026-08-07 — check the interaction, do not assume it.

### Scope agreed

**v1:** flatten; **refuse the diamond** (two bases sharing an ancestor);
**diagnose `super()`** across a flattened base. Nothing silently wrong.

**Later, separable:** synthesise an interface per flattened base so
`isinstance(d, C)` answers True and a `D` can be passed where a `C` is expected,
riding the existing RTTI interface table and IMT rather than new machinery.

Unblocks [[bug-nilpy-multiple-inheritance-does-not-parse]], which should be
re-scoped to this plan (its own option list predates the decision).

## 2026-09-19 — measured on That Space Program (frankH): which divergence decides the diamond

`tsp/ephem/__init__.py:17`, `class EphemerisMissing(EphemerisError,
FileNotFoundError)`, with `EphemerisError(Exception)` and a docstring-only body.
It is the first wall for 14 of TSP's 66 modules (TSP 13eb601, after f96cbaab9).

- **Divergence 5 (two copies of the shared ancestor) cannot fire for this
  shape.** Flattening replays the mixin's OWN body span and never its
  ancestors, and `Exception` is reached exactly once, through the real parent
  `FileNotFoundError`. Wherever every proper ancestor of each flattened mixin is
  already in the derived class's real parent chain, nothing is duplicated or
  dropped.
- **Divergence 1 (isinstance) is live and fatal to this idiom.** Probe, a
  non-diamond flattened mixin: `isinstance(e, Tag)` answers False where CPython
  answers True. A two-base exception exists so that BOTH `except
  EphemerisError` and `except FileNotFoundError` catch it. So narrowing the
  diamond refusal on its own would turn a loud refusal into a silently
  uncaught exception. The "later, separable" half of the scope above has to
  land first, or together with the narrowing.

**Constraint for the RTTI dropper (d9ed3131a priced it; unbuilt).** Once
flattened bases are recorded in the RTTI blob and `__pxxInheritsFrom` follows
them, `isinstance`/`except`/`as` DEPEND on those entries. The dropper's liveness
analysis must treat a class's flattened-base entries as reachable wherever the
class is, or it removes exactly what an `except` clause reads. The entries are
emitted fully at compile time: RTTI is read-only by default in hosted
executables (c19d88414), so nothing may patch them at run time.

### LANDED 2026-09-19 (frankH): flattened bases are bases, and the diamond is narrowed

- **is/as/except/isinstance.** `UClsFlatOwner`/`UClsFlatBase` (defs.inc)
  record every (class, flattened base) pair. rtti_emit writes them at
  +112/+120, and `__pxxInheritsFrom` follows them recursively.
  `IsClassDescOrSelf` does the same at compile time for the enumeration path
  (no builtin, ESP).
- **The diamond.** It is refused only when some flattened base has an ancestor
  that is NOT on the real parent chain (`PyMixAncestryOnChain`). That is where
  an ancestor's body would be dropped. When every ancestor is on the chain,
  the shared ancestor is reached once.
- **C3 member order.** A base written after the parent used to lose EVERY
  collision to the whole parent chain. C3 puts a base before its own
  ancestors, so it now loses only to parent-chain classes above the first
  ancestor they share. `class D(B, C)` with B(A), C(A): `d.base()` answered
  A's and now answers C's, as CPython does.
- Tests: test_nilpy_diamond_whose_ancestry_is_on_the_parent_chain (CPython
  .expected) and test_nilpy_diamond_off_the_parent_chain_fail.
- Still open: bug-n-a-subclass-of-a-class-with-a-flattened-base-calls-through-a-nil-vmt-slot
  (pre-existing on pin v411). Also divergences 3 and 6 above.
