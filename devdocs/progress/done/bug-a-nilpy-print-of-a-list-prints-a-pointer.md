---
track: A
prio: 55
type: bug
---

# NilPy: print() of a list prints the handle, not the elements

Found 2026-07-20 sweeping the one-char-string family for
[[bug-a-nilpy-one-char-literal-through-ctor-str-param]].

## Repro

```python
print("a,b".split(","))    # pxx: 129948866053376   CPython: ['a', 'b']
xs = ["a", "b"]
print(xs)                  # same
```

Indexing and iterating the list are correct — only its `print` (i.e. its `str()`
/ `repr()`) is. The value printed is the TPyList instance pointer.

## Fix sketch

`print` of a tyClass whose class is TPyList/TPyDict should call a pylib repr
helper rather than falling through to the integer path. Python's repr quotes
str elements (`['a', 'b']`) and recurses, so the helper wants the element's
variant tag — the same runtime-tag dispatch `pylen_v` / `pyord_v` already use.

Silent, and it makes the most natural debugging line in Python useless.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and the repro
matching CPython for: list of str, list of int, list of float, nested list,
empty list, and a dict (`{'k': 'v'}`).

## Log
- 2026-07-20 — resolved, commit b13557c6.
