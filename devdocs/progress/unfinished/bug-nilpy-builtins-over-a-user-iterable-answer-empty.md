---
track: N
prio: 30
type: bug
summary: "list(obj)/sorted(obj)/`x in obj` over a user class with __iter__ answer [] or raise, because the STATICALLY typed call site picks a TPyList overload instead of iterating — the runtime arms are already there"
status: working
owner: agent-AN
---

# `list(obj)` over a user iterable answers `[]`

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-15, finishing [[bug-nilpy-iterator-protocol-on-a-user-class]].
- **Half silent:** `list()` and `sorted()` answer an empty list; `in` raises.

`for x in obj` now walks a user class's `__iter__`/`__next__` correctly. The
CONSUMPTION builtins do not:

```python
class Bag:
    def __init__(self, items):
        self.items = items
    def __iter__(self):
        return BagIter(self.items)
# ... BagIter as usual

b = Bag([10, 20, 30])
print(list(b))          # CPython [10, 20, 30]   — pxx []
print(sorted(b))        # CPython [10, 20, 30]   — pxx []
print(20 in b)          # CPython True           — pxx TypeError: argument is
                        #                          not a container (no __contains__)
print(sum(Bag([1,2])))  # CPython 3              — pxx: no overload of sum matches
                        #                          these arguments (class)
```

## Cause — it is the STATIC call site, not the runtime

The runtime already knows how: `pyiter_v` and `pylist_v` both grew a
`PyUserObjHasDunder(o, '__iter__')` arm with the iterator work, so any of these
reached through a **Variant** receiver works. The failure is that a receiver
with a static user-class type never gets there — the call site resolves
`list(x)` against the `list(...)` overload set, picks the `TPyList` one, and
passes a user object to a parameter whose body reads a TPyList layout. Empty is
what that misread produces; `in` reaches a different site that refuses outright.

This is the by-name/overload family again: see
[[project_nilpy_byname_findproc_lowerings_are_the_unchecked_population]] — the
population to enumerate is every builtin whose lowering picks a pylib routine
from the argument's STATIC type.

## Shape of a fix

One rule, applied where the argument type is chosen: if the argument's class is
a user class with `__iter__`, route through
`pyiter_drain(pyiter_of_userobj(x))` (both already exist and are gate-tested by
`test/test_nilpy_iterator_protocol.npy`) instead of the container overload.
Doing it at the ONE place that maps a builtin's argument to a pylib routine is
the whole point — a per-builtin patch would be the second path that stays
broken.

## Gate

`.npy` diffed against CPython over a user iterable for each of: `list`,
`tuple`, `set`, `sorted`, `sum`, `min`, `max`, `any`, `all`, `in`,
`", ".join(...)`, and a tuple-unpack `a, b, c = obj`. Plus a control that the
same builtins over a list/dict/str/cursor are unchanged.

## Progress 2026-08-15 — the two CONVERSION POINTS are done; the overload-
## resolved builtins are not, and now have a measured boundary

Both of NilPy's "make this argument iterable" helpers grew a user-object arm,
which is the one-rule half of this ticket:

- `PyIterArgAsList` (the argument must be a LIST) now drains a user iterable,
  beside the str arm it already had — same reason, same place: the callee is
  reached by a FIXED `FindProc` index, so overload resolution never runs and
  the object was read as a TPyList header.
- `PyMakeIterOf` (the argument must be a CURSOR) now wraps one, instead of
  falling into the `pyiter_of_list` arm below it. That arm is what made
  `zip(bag, "xyz")` pair EMPTY values with the string's characters.

**Fixed and pinned by a test:** `for`, comprehensions (plain and filtered),
`enumerate`, `zip` on either side, and re-iteration through a fresh `__iter__`.
`test/test_nilpy_user_iterable_in_builtins.npy` (+`.expected`, in the Makefile),
byte-identical to CPython.

**Still broken, and this is the useful measurement:** `list(b)`, `sorted(b)`,
`tuple(b)`, `set(b)` answer empty, and `sum(b)`/`min(b)`/`max(b)`/`any(b)`/
`all(b)`/`x in b` refuse or raise. Those do NOT route through either helper —
they are ordinary OVERLOADED pylib calls, and the shared matcher picks the
`TPyList` overload for a user-class argument. So the remaining fix is a
per-argument coercion in the overload matcher: when the argument's class is a
user class with `__iter__` and the parameter wants `TPyList`/`TPyIter`, wrap it
(`pyiter_drain(pyiter_of_userobj(x))` / `pyiter_of_userobj(x)`).

That lands in `MatchProcCall*`'s side channel in `parser.inc` — Track A's
shared ground, gated on `PyExprMode` — which is why it is parked here rather
than half-applied: the two helper arms above are complete and green on their
own, and the matcher change wants a session that is not also holding six other
landed fixes. See
[[project_overload_resolution_single_side_channel_entry]] for where the hook
belongs (`MatchArgRec`, not `argTypes`).
