---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`min(3, None)` answers None where CPython raises TypeError — pyvar_gt orders None against a number instead of refusing. Low priority: comparing None is a bug in the calling program, and every shape CPython accepts is unaffected. But it is the wrong DIRECTION of laxity: we answer a question CPython refuses to answer, silently."
status: done
owner: agent-AN
---

# Comparing None with a number answers instead of raising

```python
print(min(3, None))     # CPython: TypeError   pxx: None
```

Pre-existing (the pinned compiler agrees), found 2026-08-13 while fixing
`min`/`max` with `key=None` — the guard added there deliberately does NOT cover
this shape, so that a mistaken comparison keeps failing rather than being
absorbed into the key=None escape.

## Why it is worth filing despite the low priority

This dialect is deliberately lax where CPython is strict, and that is fine when
the laxity means "we accept a program CPython rejects". Here it means something
weaker: **we answer a comparison that has no answer.** `None < 3` is not a
question with a right result, so returning one is a silent wrong value in a
program that has a bug — exactly the case where a diagnostic is worth more than
tolerance ("feedback is informative").

CPython's rule is not historic either: `None` is orderless against numbers by
design, and every dynamic language that allows it regrets it.

## Where

`pyvar_gt` (pylib) orders a VT_EMPTY payload as 0 against a number rather than
refusing. Any of `<`, `<=`, `>`, `>=` on None-vs-number reaches it; `==` and
`!=` are FINE and must stay (CPython allows those and answers False/True).

## Gate

`min(3, None)`, `3 < None`, `None > 3`, `sorted([1, None])` diffed against
CPython — each raising TypeError with the operand types named — and `None == 3`
/ `None != 3` still answering False/True. Plus the `key=None` rows of
`test_nilpy_min_max_key_none` unchanged, since they share the routine.

## Resolution (2026-08-15)

Two mechanisms served one concept, which is why the ticket's own guess at the
site was half the answer:

- `pyvar_gt` — the SORT/min/max primitive, as the ticket says;
- `pylt_v` / `pyle_v` / `pygt_v` / `pyge_v` — what a written `a < b` on a
  variant operand actually lowers to (ir.inc, the PyProgramMode arm), which
  never touches `pyvar_gt`. Fixing only the first left `3 < None` answering
  False, measured.

One refusal now serves both. `PyOrdCheck(a, b, op)` raises

    TypeError: '<' not supported between instances of 'int' and 'NoneType'

— CPython's wording, operands in SOURCE order, naming the operator the source
wrote. That last requirement is what forced the second half of the change:
`pyvar_gt` is a `>` primitive and the `<`-meaning callers reached it by SWAPPING
their arguments, so a guard inside it could only ever report `>` with the
operands backwards. They now go through a new `pyvar_lt`, which checks first and
swaps after — TPyList.sort, `min` over a list, `min` by key, two-argument `min`,
and pyeval's own `min`/`sort` twins. `max` keeps `pyvar_gt` and is right as it
stands, because CPython's max compares with `>` too.

The check also covers a str against a non-str, replacing pyvar_gt's
`comparison of a string with a number` (differently worded, and wrong about a
list). `==`/`!=` are untouched: `None == 3` is False in CPython, not an error,
and pyeq_v already has its own None arm.

NOT covered, filed separately as
`bug-nilpy-statically-clashing-operands-refuse-without-naming-the-types`:
`"a" < 3` written with two LITERALS never reaches a variant helper — the
compiler proves the clash statically and emits `PyUnsupportedOperandError`,
which takes no operands and says "unsupported operand type(s) for this
operator".

Test: `test/test_nilpy_none_comparison_raises.npy`, byte-identical to CPython,
covering the ticket's four rows plus the rest of the ordering surface, equality
and `is` staying total, and the ordinary orderings still ordering. The nine
comparison-related sibling tests (min_max_key_none, sorted_key_none,
dunder_ordering, list_ordering, sequence_ordering, char_ordering,
comparison_chaining, dataclass_order, max_min_iterables) re-run green.

## Log
- 2026-08-15 — resolved, commit 66d65dbbb.
