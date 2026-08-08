---
summary: "Decide: how should NilPy dispatch dunders on an instance whose class is known only at RUN time (container elements)?"
type: decide
track: U
prio: 45
blocked-by: [decide-nilpy-runtime-dunder-dispatch-strategy]
---

# Decide: mechanism for runtime dunder dispatch on container elements

Raised 2026-08-01 from [[bug-nilpy-dunders-not-dispatched-through-containers]],
while landing the operator-level ordering-dunder fix
([[bug-nilpy-comparison-dunders-not-dispatched]]).

## The situation

Dunder dispatch today is entirely COMPILE-TIME: the parser sees two `tyClass`
operands (or a `str()` of a known class), resolves the method against the
operand's static class, and builds the call. That covers every direct use and is
already landed for `__eq__`, `__lt__`/`__le__`/`__gt__`/`__ge__`, `__len__`,
`__contains__`, `__call__`, `__getitem__`, `__setitem__`, `__str__`.

It covers NOTHING reached through a container. A list/dict element is a
`Variant` holding the instance handle, so the class is a run-time fact. Measured
consequences: `print([obj])` prints an empty string per element (silent, wrong),
`sorted([obj, obj])` raises "expected a number, got object".

This is one missing capability wearing several hats — `__repr__`, `__str__`, the
four ordering dunders and `__eq__` all need the same lookup.

## The fork

1. **Runtime RTTI lookup in pylib.** `pyvar_gt`/`pystr_of` resolve the method by
   NAME on the `TObject` via the existing RTTI method table (VMT-8) and call it
   indirectly. Most general — one implementation serves every dunder and every
   container, including heterogeneous lists, which is what Python actually is.
   Cost: a name lookup per comparison (a sort does O(n log n) of them), it
   depends on RTTI being emitted for every NilPy class, and
   `project_rtti_method_table_multi_consumer_stride_landmine` warns that table
   has three consumers that must change together.
2. **Per-class dunder slot table stamped at construction.** Give each NilPy class
   a small fixed record of dunder entry points (repr/str/lt/le/gt/ge/eq) reachable
   from the handle, so the runtime indexes rather than searches. Much faster per
   call and no RTTI dependency; costs a new per-class structure and a decision
   about where it hangs (VMT-adjacent, with the layout risk that implies).
3. **Compile-time monomorphisation where the element type is inferable.** When a
   list is provably homogeneous, specialise the comparator at the call site.
   Cheapest and needs no runtime machinery, but it fails exactly where Python is
   most Python (heterogeneous or inference-defeating cases) and would silently
   fall back to today's wrong behaviour unless paired with a hard error.
4. **Raise, don't guess — make it loud and stop there.** Keep dispatch
   compile-time only, but make the container paths RAISE a clear TypeError
   instead of printing empty strings. Small, honest, closes the silent-wrong half
   immediately; leaves `print([obj])` and `sorted()` unsupported.

## Recommendation

**4 first, then 1.** The empty-string print is the genuinely dangerous defect and
option 4 retires it in an afternoon without committing to a mechanism — the same
"make it loud first" move [[decide-class-namespace-scoping]] took with its
stopgap. Then 1 for the real fix: generality is the point here (Python containers
are heterogeneous by nature), and option 2's speed only matters once something
sorts large object lists, which nothing in the corpus does yet. Option 3 alone is
a trap — it is the one that keeps a silently-wrong path alive.

Note options 1 and 2 are not exclusive: 2 is a cache in front of 1 if profiling
ever demands it.

## What unblocks on this

[[bug-nilpy-dunders-not-dispatched-through-containers]] is `blocked-by` this
ticket. `feature-nilpy-arithmetic-ordering-dunders` (the umbrella) will hit the
identical wall for `__add__` and friends, so whatever is decided here sets that
shape too.

## 2026-08-01 — a THIRD symptom reached this same wall

Landing the truthiness fix
([[bug-nilpy-bool-protocol-ignored-object-always-truthy]]) fixed `if o:` for a
statically-typed receiver but not for an untyped function PARAMETER:

```python
o = BoolFalse()
if o: ...              # falsy   — correct
def show(x):
    if x: ...
show(o)                # TRUTHY  — wrong, x is a variant at run time
```

So the mechanism decided here now gates three distinct symptoms, not two:

1. dunders on a container ELEMENT (`print([obj])`, `sorted()`) — the original.
2. `__hash__`/`__eq__` for an object used as a dict KEY
   ([[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]]).
3. any dunder on an object reached as an untyped PARAMETER — which is ordinary,
   idiomatic Python and probably the most common of the three in real code.

Point 3 raises the stakes on option 4 ("raise, don't guess"): raising for every
truth test on a variant-typed parameter would break working programs, since
"any instance is true" is the correct answer whenever the class declares no
dunder. So option 4 is a viable stopgap for `print([obj])` but NOT for
truthiness — the fallback there must stay silent and correct. Worth weighing
when picking between 1 and 2: whatever lands has to answer "does this class
declare `__bool__`?" cheaply at run time, for objects that mostly do not.

---

## POSTPONED — 2026-08-01 (user)

> "#1 needs a careful thought."

Deliberately not answered today. Not blocked on information — blocked on
judgement, which is what Track U is for.

Carry forward when it is picked up: the **third symptom found on 2026-08-01
(dunders via an untyped PARAMETER) narrowed the option space after the options
were written.** Option 4 ("raise, don't guess") is still a fine stopgap for
`print([obj])`, but it cannot be applied to truthiness — "any instance is true"
is the *correct* answer when a class declares no `__bool__`, so raising there
would break working programs. That means whichever of 1/2 lands must answer
**"does this class declare `__bool__`?" cheaply at run time, for objects that
mostly do not** — a constraint that did not exist when the options were drafted.

Still `blocked-by` this: [[bug-nilpy-dunders-not-dispatched-through-containers]],
and [[feature-nilpy-arithmetic-ordering-dunders]] will hit the identical wall for
`__add__`.

## 2026-08-02 — superseded in scope by `decide-nilpy-runtime-dunder-dispatch-strategy`

Both tickets ask the same question — how does NilPy dispatch a dunder when the
instance's class is known only at run time — from two entry points (this one from
container elements, the other from Variant-held globals and parameters). They
list the same three options and reach the same recommendation.

Leaving both filed rather than merging one away, because they record different
symptom sets and neither is resolved. But **one answer settles both**, and
[[decide-nilpy-runtime-dunder-dispatch-strategy]] is the broader statement (a
container element is one way to end up Variant-held), so answer that one and
apply it here. Do not decide them separately — two different mechanisms for one
problem is the outcome nobody wants.

## 2026-08-03 — edge recorded, so the two cannot be decided separately

The supersession note above says *"do not decide them separately — two different
mechanisms for one problem is the outcome nobody wants"*, and deliberately kept
both filed because they record different symptom sets. But nothing enforced it:
both sat in `backlog/` as independently rankable Track U items (p60 and p70), so
`progress.sh next` could hand this narrower one to an agent to answer on its own.

Recorded `blocked-by: [decide-nilpy-runtime-dunder-dispatch-strategy]` and moved
to `blocked/`. Neither ticket's content is merged away — this one keeps its three
symptom sets and the POSTPONED carry-forward. Only the ordering is now explicit:
answer the broad one, then apply it here.

## DECIDED 2026-08-08 — answered by its blocker

[[decide-nilpy-runtime-dunder-dispatch-strategy]] chose **option B**, and that
answers this one too: when the class is known only at run time, dispatch is a
**compile-time-generated switch on class identity**, not a lookup. The compiler
sees every class declaring the dunder (closed world), so it emits the table; the
runtime only takes an indirect call through it.

Reserve a hard failure for "no class declares it"; several candidates is the
normal case and is what the switch is for. Parked with its blocker.
