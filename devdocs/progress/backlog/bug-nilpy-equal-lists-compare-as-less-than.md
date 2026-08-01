---
summary: "NilPy: `[1,2] < [1,2]` returns True and `[1,2] >= [1,2]` returns False — two EQUAL lists compare as less-than, silently inverting sort/threshold logic"
type: bug
track: N
prio: 65
---

# Equal lists compare as less-than

- **Type:** bug (NilPy semantics, silent wrong value) — **Track N**
- **Opened:** 2026-08-01, from the CPython differential sweep (1094 cases,
  self-hosted binary at `3f2c5b915`).

## Measured

Both operands are lists, so this is an operation CPython defines — not a
type-mismatch case:

| expression | CPython | pxx |
| --- | --- | --- |
| `[1, 2] < [1, 2]` | `False` | **`True`** |
| `[1, 2] >= [1, 2]` | `True` | **`False`** |
| `[1, 2] <= [1, 2]` | `True` | `True` (correct) |
| `[1, 2] > [1, 2]` | `False` | `False` (correct) |

So exactly the two strict/non-strict boundaries at EQUALITY are inverted. `<`
and `>=` are each other's negation, which is consistent with a single wrong
answer for "are these equal?" propagating to both.

Note `<` on *unequal* lists is fine — `[1] < [1, 0]` is asserted by
`test_nilpy_mixed_type_operands` and passes. The bug is specific to the
lists comparing **equal**, which is precisely the boundary case a test written
from the happy path would not cover.

## Why it matters

`<` returning True for equal elements breaks the strict-weak-ordering contract
every sort depends on. A comparison sort given this predicate can produce a
wrong order or loop, and threshold logic (`if version >= minimum:`) takes the
wrong branch at exactly the boundary it exists to test. Silent in every case.

## Cause (to confirm)

`pyvar_gt` (`compiler/builtin/pylib.pas`) implements lexicographic list
comparison: it walks to the first differing element, and falls back to
`la > lb` (length comparison) when no element differs. For two equal lists that
correctly yields `False`.

So `>` and `<=` — the two that are correct — look like the direct users, and
`<`/`>=` are presumably derived by swapping operands or negating somewhere that
gets the equal case wrong (e.g. `a < b` lowered as `pyvar_gt(b, a)` would be
`False` for equal lists, so the inversion is more likely in the negation).
**Measure before concluding**: this reasoning is a lead, not a diagnosis — dump
the lowering with `PXXDBG` (`a.ir:<proc>`) and check which helper each of the
four operators actually reaches.

## Scope to check when fixing

The same equal-operand boundary for the other lexicographic types, none of which
this sweep isolated separately: tuples (the same `TPyList` row), `bytes`,
nested lists (`[[1],[2]] < [[1],[2]]`), and strings.

## Gate

`make test-nilpy` + self-host byte-identical, plus the four rows above added to
the existing list-comparison cases in `test_nilpy_mixed_type_operands`, with
CPython's own output — and equal-operand cases for tuples/bytes/nested lists in
the same pass, so the boundary is covered for the whole family rather than just
the one spelling that was measured.
