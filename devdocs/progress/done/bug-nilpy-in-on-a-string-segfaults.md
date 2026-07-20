---
track: N
prio: 70
type: bug
owner: agent-n
---

# NilPy: `sub in s` on a STRING segfaults

Found 2026-07-20 sweeping string operations against CPython.

```python
s = "hello"
print(s == "hello")   # True    fine
print(s < "world")    # True    fine
print("ell" in s)     # SEGFAULT — CPython: True
```

## Cause

`in` dispatches to a pylib helper chosen by the container. There were two
cases — dict (key membership) and everything-else (list element membership) —
and a string fell into the second, so `pycontains` read the string HANDLE as a
`TPyList` and scanned its header words as 16-byte variant slots.

Pre-existing: the dict case was added this session, but a string always fell
through to the list helper.

## Fix (in hand)

A third case: a string base dispatches to `pystr_contains`, which is
SUBSTRING containment — what `in` means for a string in Python, not element
membership. The empty string is contained in everything, as in CPython.

Getting the dispatch wrong here is a CRASH rather than a type error, which is
why the three cases are now written out together with that noted.

## Gate

`test-nilpy` green with the cases added to `test_nilpy_membership.npy` +
`--tier quick` + self-host byte-identical + `make fpc-check`.

## Log
- 2026-07-20 — resolved, commit c49064af.
