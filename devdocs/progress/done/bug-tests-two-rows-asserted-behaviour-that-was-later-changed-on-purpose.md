---
track: N
prio: 40
type: bug
---

# Two Nil Python rows asserted behaviour that was later changed on purpose

Found 2026-10-19 in the full row sweep. Neither row could fail while the recipe
was stopping at row 593, so both went stale without anyone seeing it.

- `test_nilpy_optional_int_none` expected `int(None)` to print `0`. CPython
  raises TypeError, and 0f6416c42f made pxx raise too. The row now prints the
  None value and catches the TypeError (7, 42, None, TypeError, matching CPython).
  `pyvar_to_int`'s internal None→0 sentinel is unchanged.
- `test_nilpy_dataclass_frozen_fail` expected `@dataclass(frozen=True)` to be
  refused. ae615953df (10-09) deliberately changed that to accepted-with-warning
  for the TSP port. The row now compiles the file and greps for the warning.
