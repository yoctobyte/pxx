---
track: N
prio: 30
type: bug
summary: "list(obj)/sorted(obj)/`x in obj` over a user class with __iter__ answer [] or raise, because the STATICALLY typed call site picks a TPyList overload instead of iterating — the runtime arms are already there"
status: done
owner: claude-AN
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

## Resolved 2026-08-15 — and the parked plan was aimed at the wrong layer

Done, but NOT where the progress note above predicted. That note said the fix
was "a per-argument coercion in the overload matcher" in Track A's shared
`MatchProcCall*`. Measured, that is wrong: `list(bag)` never picks the
`list(TPyList)` overload at all. It picks **`list(const v: Variant)`** — the
user object is boxed and dispatched at RUN TIME — so no matcher change could
have fixed it, and the one I started with fixed only the `sum`/`min`/`max`
family. Reasoning about which overload wins was cheaper than dumping it, and it
was wrong; the parameter kind printed `22` (tyVariant) the moment I looked.

### The actual defect: ONE chain, written out FIVE times

Every "turn this object into a sequence" site is a hand-copied ladder of `is`
tests, and the copies had drifted:

| site | knew list/dict | bytes | cursor | range | user `__iter__` |
| --- | --- | --- | --- | --- | --- |
| `pylist_v` | yes | yes | yes | yes | **yes** (the only one) |
| `list(Variant)` | yes | yes | yes | yes | no |
| `tuple(Variant)` | yes | yes | yes | yes | no |
| `sorted(Variant)` (pyeval) | yes | no | yes | yes | no |
| `pyset_of` | yes | no | **no** | **no** | no |

So `list(bag)`/`tuple(bag)`/`sorted(bag)` answered `[]`, and `set(range(3))` —
nothing to do with this ticket — refused, because pyset_of had drifted furthest.

Replaced by one exported helper, **`pyseq_of_obj(o): TPyList`** (pylib
interface): the whole ladder once, answering nil when `o` is none of them so
each caller keeps its own refusal wording and its own kind stamping (a set
DEDUPLICATES, so it adds the elements rather than adopting the list). All five
sites now call it.

### Two more defects found on the way, both fixed here

1. **`pyiter_of_userobj` refused a correct program.** The overwhelmingly common
   way to write the protocol — `def __iter__(self): return iter(self.items)` —
   returns a pylib CURSOR, and the `__next__` probe only recognised a USER
   class, so it raised "iter() returned non-iterator of type 'TPyIter'". A
   TPyIter IS an iterator; it is now handed back as-is.
2. **A no-arg dunder returning an OBJECT handed back a released one.** With (1)
   fixed, the returned cursor arrived with `FObj = nil` and drained to `[]`.
   `PyUserObjNoArgDunder`'s RetKind=6 arm did `res := TObject(fo(...))`, and the
   class-typed call temporary is released at the end of that statement while the
   Variant box does not retain — so the caller got a freed object. A
   `PXXObjRetain` before the box fixes it. **This is not specific to
   `__iter__`**: it is every no-arg dunder that returns an object, through the
   one dispatcher. The direct call `q = a.mk()` was clean under
   `-dPXX_HEAP_DEBUG`, which is what proved the RTTI path was the difference.

### Also fixed, same rule, other sites

- `PyDrainIfCursor` (tuple-unpack, `"".join`, `x in obj`) materialises a user
  iterable too — `a, b, c = bag` refused with "not a list, tuple or variant"
  and `x in bag` raised. Guarded on the class NOT declaring `__contains__`,
  because the `in` caller dispatches to that method after this call and CPython
  asks it first. Corner deliberately left: a class declaring BOTH `__contains__`
  and `__iter__` still cannot be tuple-unpacked.
- `PyFixIterableArgs` (new, pyparser.inc; called from the two call-parse sites
  in parser.inc): drains a user iterable when no overload matched and retries
  the match once, which is what gives `sum(bag)`/`min`/`max`/`any`/`all` the
  TPyList row. Keyed on the PARAMETER, never on a builtin name.

### Gate

`test/test_nilpy_user_iterable_in_builtins.npy` EXTENDED rather than a second
file (it already owned this concept): the conversion points it covered, plus
`list`, `tuple`, `set`, `sorted` (with `reverse=`), `sum`, `min`, `max`, `any`,
`all`, `in`, a three-name unpack, `", ".join(...)`, both a `__iter__`-returns-
`iter(...)` class and a self-iterator with `__next__`, the empty case, a
`__contains__` class proving the method still wins, and controls over
list/dict/str/bytes/range/cursor receivers. Byte-identical to CPython.
`gate.sh quick` GREEN. `compiler/builtin/**` changed, so this is pinned.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
