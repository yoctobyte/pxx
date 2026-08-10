---
summary: "NilPy: __repr__/__str__ of a class instance held in a container silently print EMPTY; ordering/sorted raise — no runtime dunder dispatch on a Variant"
type: bug
track: N
prio: 45
blocked-by: []   # decided 2026-08-08: option B
---

# NilPy: dunders don't dispatch when the instance is reached through a container

- **Type:** bug (NilPy runtime dispatch) — **Track N**
- **Opened:** 2026-08-01, split out of
  [[bug-nilpy-comparison-dunders-not-dispatched]] while landing the operator-level
  ordering fix. That ticket's operator path is fixed; this is the OTHER route it
  exposed, and it is a different mechanism, not a leftover.

## Measured boundary (2026-08-01, self-hosted binary at `da085e9de` + the
ordering-dunder fix)

```python
class C:
    def __init__(self, v): self.v = v
    def __repr__(self): return "C" + str(self.v)
    def __str__(self):  return "S" + str(self.v)
    def __lt__(self, o): return self.v < o.v
a, b = C(1), C(2)
print("direct str:", str(a))          # CPython S1     pxx S1     OK
print("direct lt:",  a < b)           # CPython True   pxx True   OK (just fixed)
print("in list:",    [a, b])          # CPython [C1, C2]  pxx "[, ]"   WRONG, SILENT
print("str of elem:", str([a][0]))    # CPython S1     pxx ""     WRONG, SILENT
print(sorted([b, a]))                 # CPython [C1, C2]  pxx TypeError
```

The split is exact and mechanical:

- **Static class known at the call site** → the compile-time dispatch in
  `parser.inc` / `pyparser.inc` fires and the dunder runs. Correct today.
- **Instance reached through a container** (the element is a `Variant` holding
  the handle, so the class is known only at RUN time) → no dispatch exists at
  all. `pystr_of` yields an empty string and `pyvar_gt` falls through to
  `pyvar_to_int` ("expected a number, got object").

## Why this is the dangerous half

`sorted()`/`min()`/`max()` at least RAISE. `print([obj])` does not — it prints
`[, ]`, an empty string per element, which is a plausible-looking wrong value
rather than a failure. That is exactly the repo's expensive-bug shape: no crash,
no location, wrong output far from the cause.

## Cause

There is **no runtime dunder dispatch in pylib at all** — verified by reading
`pyvar_gt` (`compiler/builtin/pylib.pas`, the sort/compare path) and by the
`__repr__` measurement above. Both would need to look up a method BY NAME on an
arbitrary `TObject` at run time. The machinery to do that plausibly exists (RTTI
method reflection, VMT-8 — `project_rtti_reflection_and_overload_landmines`), but
nothing wires it to the dunder names.

## Blocked on a design call

How container-element dispatch should work is a real fork (runtime RTTI lookup in
pylib vs. compile-time monomorphisation vs. a per-class dunder vtable stamped
into the handle), with different cost/generality trade-offs and a self-host
blast radius that differs a lot between them. Filed as
[[decide-nilpy-runtime-dunder-dispatch-mechanism]] — do NOT guess a direction
here; pick it there first.

`blocked-by: decide-nilpy-runtime-dunder-dispatch-mechanism`

## Gate (when it lands)

`make test-nilpy` + self-host byte-identical, and the boundary script above
diffed against CPython (`tools/pydiff.py`) — all five lines, not just the
sorted one.

## 2026-08-01 — consolidated: same root as two sibling tickets

Reproduced exactly as filed (`[a, b]` -> `[, ]`, `str([a][0])` -> empty,
`sorted()` -> TypeError, while direct `str(a)` and `a < b` are correct).

This is NOT a separate mechanism from the arithmetic case: dunder dispatch is
compile-time only, so ANY route that puts the instance in a Variant loses it —
containers here, a widened global elsewhere, a Variant parameter next. Folded
into [[feature-nilpy-runtime-dunder-dispatch-on-variants]] so the three do not
each grow a private runtime path, which is precisely how the `not <x>` family
came to need three separate fixes.

**blocked-by:** [[decide-nilpy-runtime-dunder-dispatch-strategy]]

## 2026-08-03 — dependency recorded in frontmatter

The body named the blocker (twice, under two different slugs) but no
`blocked-by:` edge existed. The edge is the broader of the two decide tickets,
[[decide-nilpy-runtime-dunder-dispatch-strategy]], per the supersession note on
[[decide-nilpy-runtime-dunder-dispatch-mechanism]]: one answer settles both, and
deciding them separately is the outcome that note warns against.

## 2026-08-09 — the `__getitem__` half, measured (a variant PARAMETER)

The ticket predicted "a Variant parameter next". It is:

```python
class Vec:
    def __init__(self, xs): self.xs = list(xs)
    def __getitem__(self, i): return self.xs[i]

v = Vec([7, 8])
print(v[0])                       # 7 — static receiver, correct
def first(w): return w[0]
print(first(v))                   # CPython 7;  pxx TypeError: object is not subscriptable
print([w[0] for w in [v]])        # same
print(sorted([v], key=lambda w: w[0]))   # same
```

So the SUBSCRIPT protocol belongs on the blast-radius list alongside
`__repr__`/`__str__`/ordering — and per
[[project_nilpy_subscript_protocol_has_three_members]] that is three members
(`__getitem__` / `__setitem__` / `__delitem__`), not one, whenever this is
built. `pyeval.pas`'s `PySubscriptGet` is where the tag-7 arm ends today: it
knows TPyList/TPyDict/TPyBytes and nothing else.

No fix attempted — same root, same blocker, deliberately not grown a private
path. Found by a Vec/Mat program diffed against CPython.

## Unblocked 2026-08-10 — and the decision singles THIS one out to do first

[[decide-nilpy-runtime-dunder-dispatch-strategy]] is in `decided/`: **option B**
(a compile-time-generated switch on class identity, not a reflective lookup),
with dirty-class detection reusing the existing `PyDynAttrEverAssigned`
predicate rather than inventing a second notion of "dirty".

The broad strategy is parked to rainy-day — but the decision explicitly names
this ticket's shape as the piece worth taking first:

> If anyone picks up a piece, the narrow one comes first: pylib's container
> renderer has no ROUTE to dispatch that already works — measured 2026-08-07,
> `o.__repr__()` on an untyped parameter and over a heterogeneous list both
> reach the right class today. That is a HOOK, not a dispatcher, and it is most
> of the visible pain.

So this is a hook into dispatch that already works, not new dispatch machinery —
much smaller than the parked strategy, and it is where the visible symptom
(`print([a, b])` rendering `[, ]`) lives. The standing rule from
[[decide-nilpy-class-attribute-instance-read-model]] applies: correct or a clear
error, never silent.
