---
track: N
prio: 45
type: bug
blocked-by: []
summary: "`hasattr([1], 'add')` and `hasattr([1], 'update')` are True: list and set are both TPyList at run time, so every `is`-test-based introspection answers set questions about a list. `type(x).__name__` DOES tell them apart, so the discriminator exists and the predicate is not using it."
---

# A list and a set share one class, so introspection cannot tell them apart

Filed 2026-08-26 while resolving
[[bug-n-hasattr-through-an-untyped-parameter-is-always-false]]. Pre-existing for
`add`/`discard`/`union`; that fix adds `update` and the other set-only aliases to
the same list, which is stated as an explicit trade in its resolution rather than
worked around.

## Measured (self-hosted, at the fix's sha)

```python
def h(x, n):
    return hasattr(x, 'update')      # and 'add', per row
print(type([1]).__name__, type({1, 2}).__name__)    # list set   — both, correct
```

| | CPython | pxx |
| --- | --- | --- |
| `hasattr([1], 'add')` | False | **True** (pre-existing) |
| `hasattr([1], 'update')` | False | **True** (new with the hasattr fix) |
| `hasattr({1, 2}, 'add')` | True | True |
| `hasattr({1, 2}, 'update')` | True | True (was False) |
| `type([1]).__name__` | `list` | `list` |
| `type({1, 2}).__name__` | `set` | `set` |

## Cause

`list` and `set` are both **`TPyList`**. Every introspection path that decides
by class identity — the `AN_IS_TEST` chain `PyHasAttrRuntimeChain` builds, and
pylib's `PyFindMethByName(GetInstanceRTTI(obj), …)` — therefore cannot separate
them, and answers the union of both Python types' surfaces for either.

The interesting part is that the information is not missing:
`type(x).__name__` / `pytype_name_v` answers `list` vs `set` correctly, so
whatever distinguishes them at run time is reachable. The predicate is deciding
by the wrong key, not from missing data.

## Not just hasattr

`isinstance` is worth measuring on the same pair before choosing a fix — the
NilPy charter's own worked example is that `isinstance(t, list)` answering True
for a non-list IS a bug, "because ordinary working code branches on it"
(`devdocs/dev/nilpy-semantics-divergences.md`). If `isinstance(a_list, set)` is
also True, that is the same defect and the fix should serve both, not grow a
second mechanism.

## Shape of the fix

Do not add a per-name exclusion list to `hasattr` — that is the second path that
stays broken. Either give the two Python types two classes (`TPySet` deriving
from or beside `TPyList`), or make the introspection predicates decide on the
same run-time discriminator `pytype_name_v` already uses instead of on class
identity. The first makes `is` correct everywhere for free and is the reason to
prefer it; measure what it costs in pylib first.

## Gate

The table above as a `.npy` with a CPython-generated `.expected`, plus the
`isinstance` rows, plus the calls (`{1,2}.update({9})` and `[1].append(9)`) still
working next to them.

## Fixed 2026-11-10

Measured first: `isinstance` already tells the four apart. `hasattr` was wrong
in both directions, on literal and computed names alike: `append` on a tuple
or set answered True, and `update` on a set answered False. `__contains__` and
`__iter__` on a list or set answered False.

The fix uses the run-time discriminator the ticket points at (TPyList.FKind,
which `type()` reads). It is not a per-name exclusion list:
- pylib `pyseq_hasattr_p` / `_v` answer from each kind's real surface: the
  methods plus the container dunders, as in CPython's dir().
- This applies only for a name on one of the four surfaces. Any other name (a
  subclass's own method, an unusual dunder) keeps the class-identity answer,
  so `class L(list)` with its own `add` still answers True.
- The parser wraps both hasattr exits (literal name and computed name) when
  the receiver is a variant or a static TPyList (PySeqHasAttrFixable), and
  binds the receiver and name once.

Test: test/test_nilpy_hasattr_tells_list_tuple_and_set_apart.py, with
expected output = python3.
