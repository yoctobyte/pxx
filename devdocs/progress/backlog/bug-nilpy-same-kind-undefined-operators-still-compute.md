---
track: N
prio: 60
type: bug
---

# Same-kind undefined operators still compute silently (`"ab" - "ab"` → 0)

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, the deliberate residue of
  [[bug-nilpy-static-typed-operands-skip-mixed-type-guard]], which fixed the
  DIFFERING-kind half.

## What still diverges

Both operands the same Python kind, operator undefined for that kind:

| expression | CPython | pxx |
| --- | --- | --- |
| `"ab" - "ab"` | TypeError | **`0`** |
| `"ab" / "ab"` | TypeError | a float |
| `"ab" // "ab"` | TypeError | a number |
| `[1] // [2]` | TypeError | a number |
| `[1] % [2]` | TypeError | a number |

## Why the sibling fix deliberately stopped short

`IRPyStaticPairUndefined` fires only when the two operand KINDS DIFFER, because
**pxx backs a Python `set` with `TPyList`**:

```python
set([1, 2, 3]) - set([2])       # -> [1, 3], works today and must keep working
```

Sets and lists share a row, so "list minus list is undefined" is not statically
decidable — it would break set difference, a real feature. Rather than guess,
the same-kind half was left alone and filed here.

## Fix shape (needs a decision, not just code)

Two directions, and picking between them is the actual work:

1. **Distinguish sets from lists in the type system** — a flag on the rec, or a
   distinct `TPySet` row. Then `list - list` is rejectable while `set - set`
   stays defined, and this becomes the same table-driven rule the differing-kind
   half already uses. Bigger change; touches how sets are constructed and
   printed (they already diverge in repr: `[1, 3]` vs CPython's `{1, 3}`).
2. **A runtime kind check on the same-kind path** — lower these to a helper that
   inspects the actual objects and raises. Cheaper, keeps sets working, costs a
   call on a path that is currently pure arithmetic.

`str`-vs-`str` has no set-like ambiguity, so `"ab" - "ab"` could be rejected
statically today without either — worth doing first as a cheap, safe slice if
this ticket is picked up before the set question is settled.

If the set-vs-list modelling question is contested, escalate it as a Track U
`decide-*` rather than half-implementing one direction.

## Gate

A `.npy` diffed against CPython covering the table above, plus proof that
`set(...) - set(...)`, `set` union/intersection, list concat/repeat and string
repeat all still work.

## 2026-08-01 — the str-vs-str SLICE is fixed; list/dict/bytes remain

This ticket itself identified str as the cheap safe slice, and that is what
landed (`4e949bb9b`):

| expression | before | after |
| --- | --- | --- |
| `"ab" - "ab"` | `0` | `TypeError` |
| `"ab" / "ab"` | `1.0` | `TypeError` |
| `"ab" // "ab"` | `1` | `TypeError` |

`str` carries no set-like alter ego, so same-kind `str` is statically
rejectable with no ambiguity. Ordering is untouched (`"aa" < "bb"` is defined)
and `%` stays exempt as formatting. Covered in
`test/test_nilpy_static_mixed_type_guard.npy`.

**Still open, and still for the reason this ticket was filed:** the same-kind
`list` / `dict` / `bytes` cases — `[1] // [2]`, `[1] % [2]` and friends. pxx
backs a Python `set` with `TPyList` and `set([1,2,3]) - set([2])` works today
and must keep working, so "list minus list is undefined" is not statically
decidable. That still needs either a set-vs-list distinction in the type system
or a runtime kind check, and the choice between them is the actual work — see
the two directions costed above.

Reduced in scope, not resolved.
