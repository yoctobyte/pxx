---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`[].pop()` said \"list index out of range\" where CPython says \"pop from empty list\"; `[1].pop(3)` said the same where CPython says \"pop index out of range\"; and `(1,)[5]` said \"list\" where CPython says \"tuple\". A program prints these."
---

# IndexError messages name neither the sequence kind nor the operation

Found 2026-08-16 in the same differential sweep as
[[bug-nilpy-a-failed-file-syscall-loses-both-its-class-and-its-message]], and
it is the same shape: nothing crashes, no value is wrong, the program just
SAYS something different.

## Measured

| | CPython | NilPy |
| --- | --- | --- |
| `[].pop()` | `pop from empty list` | `list index out of range` |
| `[1].pop(3)` | `pop index out of range` | `list index out of range` |
| `(1,)[5]` | `tuple index out of range` | `list index out of range` |
| `[1][5]` | `list index out of range` | agreed |
| `"ab"[5]` | `string index out of range` | agreed |

## Cause

One `PyIndexError` raiser with one hard-coded string, used by `PyListFix` for
every sequence and every operation. NilPy has ONE `TPyList` behind list, tuple
and set — so the kind cannot come from the class and has to come from `FKind`,
which exists for exactly this reason (it is what stopped a set from printing as
a list, `bug-nilpy-list-tuple-and-set-are-indistinguishable-to-isinstance`).

## Fix

`PySeqIndexError(l)` reads `FKind` and says `tuple` or `list`; `TPyList.pop`
and `pop_at` raise the two pop-specific messages CPython uses before they reach
the shared path.

## Gate

`test/test_nilpy_indexerror_message_names_the_kind.npy` — the five message rows
plus the ordinary pop/index paths that must not move, diffed against CPython.
