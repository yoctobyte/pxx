---
track: N
prio: 35
type: bug
blocked-by: []
status: done
owner: claude-AN
---

# `list.sort()` on user objects with `__lt__` raises a runtime TypeError instead of using it

Found by proactive CPython-diff sweeping, right after fixing comparison-
adjacent arithmetic dunders (`bug-nilpy-arithmetic-operator-dunders-not-
dispatched`, `bug-nilpy-unary-neg-dunder-not-dispatched`) — this is the same
family of gap for the COMPARISON dunders specifically, surfaced through
`sort()`'s element comparisons.

```python
class Point:
    def __init__(self, x, y):
        self.x = x; self.y = y
    def __lt__(self, other):
        return (self.x, self.y) < (other.x, other.y)
pts = [Point(2,1), Point(1,2), Point(1,1)]
pts.sort()
```
CPython sorts using `__lt__`: `[(1,1), (1,2), (2,1)]`. pxx: runtime
exception —
```
Unhandled exception: TypeError: expected a number, got object
```
— `list.sort()`'s internal comparison assumes a numeric/string element and
never consults a class's `__lt__` (or `__eq__`/`__gt__`/etc.) at all.

## Scope note

**Confirmed separately**: a bare `<`/`==` EXPRESSION between two statically
class-typed operands (`Point(1,1) < Point(1,2)`, `a == b`) already dispatches
correctly to `__lt__`/`__eq__` — that parse-time comparison path is fine. So
this gap is ISOLATED to `.sort()`'s own internal element comparison, which
must go through a different, purely-runtime Variant-comparison helper
(operating on two boxed Variants with no static class context, likely near
`pyvar_lt`/`PyVarLess` in `compiler/builtin/pylib.pas`) that never got
taught to check for and call a class's own comparison dunder. The fix
therefore needs a RUNTIME class-tag check + dynamic method dispatch — the
same shape as the already-open `feature-nilpy-runtime-method-dispatch-on-
variant` — not a parse-time change like the arithmetic dunder fixes used.

Not attempted this pass — needs its own investigation into exactly which
runtime comparison helper `.sort()`'s internals call, and how to invoke a
class's method generically from that context (pylib.pas has no visibility
into user-defined classes compiled later, the same constraint noted in
`bug-nilpy-list-of-custom-objects-loses-repr-str`).

## Gate

A `.npy` case sorting a list of user objects with `__lt__`, diffed against
CPython, gated in `test-nilpy` + `--tier quick` + self-host byte-identical.

## Fixed (2026-08-08, claude-AN)

`.sort()`, `sorted()`, `max()`, `min()`, `reverse=` and `key=` over user objects
all match CPython now.

### Where it actually was

The ticket's guess was right: `pyvar_gt` (pylib.pas) — it handled two
TPyList sequences and the scalar families, then fell through to `pyvar_to_int`,
which is where "expected a number, got object" came from. A user-object arm now
sits directly after the sequence arm.

### The REFLECTED arm is the one that carries it

CPython tries `a.__gt__(b)` then `b.__lt__(a)`. For sorting, the second is what
matters: Python's sort requires only `__lt__`, so the idiomatic sortable class
defines `__lt__` and **no `__gt__` at all** — the direct lookup finds nothing
every time. Both arms are implemented and both are in the test; a class with
only `__gt__` exercises the direct one.

### Not a fourth copy of the dispatch

This would have been the fourth "find a dunder in the RTTI and call it" in
pylib (`__repr__`/`__str__`, `__eq__`, `__hash__`, now `__gt__`/`__lt__`), so
the `__eq__` version added hours earlier was first factored into one
`PyUserObjBoolDunder(selfObj, otherObj, otherV, dunder, res)`. `PyUserObjEq`
and the new `PyUserObjGt` are now four lines each and differ only in their
reflection rule. Both `__eq__` shapes (Variant `other`, and a
@dataclass-generated class-pointer `other` with its exact-class guard) are
therefore handled for ordering too, for free.

### The control that must stay

A class with NO comparison dunder still raises `TypeError`. Silently ordering by
handle would produce a plausible-looking but meaningless order — the expensive
failure mode. It is asserted in the test, not just left to chance.

### Verification

- New `test/test_nilpy_sort_lt_dunder.{npy,expected}` (`.expected` from
  CPython): in-place `.sort()`, `sorted()`, `reverse=`, `max`/`min`, `key=`, a
  `__gt__`-only class, the expression path that already worked, scalar/tuple
  controls, and the no-dunder TypeError control. Wired into `test-nilpy`.
- `test_nilpy_{list_sort_method,sorted_dict_key,sorted_key_dispatch,
  sorted_pairs,sorted_sequences,list_ordering,dunder_ordering,
  membership_eq_dunder}` all re-diffed against CPython: match.
- `tools/gate.sh quick` GREEN.

### Filed alongside
[[bug-nilpy-dataclass-keyword-arguments-do-not-parse]] — `@dataclass(order=True)`
does not parse, so it could not be the third case in this test. Loud, not
silent; the workaround is the hand-written `__lt__` the test uses.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.
