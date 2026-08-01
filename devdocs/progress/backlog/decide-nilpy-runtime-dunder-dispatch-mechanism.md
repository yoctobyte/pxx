---
summary: "Decide: how should NilPy dispatch dunders on an instance whose class is known only at RUN time (container elements)?"
type: decide
track: U
prio: 60
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
