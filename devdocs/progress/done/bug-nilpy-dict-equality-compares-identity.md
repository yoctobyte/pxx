---
track: N
prio: 70
type: bug
---

# `{"k": 1} == {"k": 1}` is False — dict equality compares identity, not value

```python
print({"k": 1} == {"k": 1})   # CPython: True    pxx: False
a = {"x": 1}
b = {"x": 1}
print(a == b)                 # CPython: True    pxx: False
print(a == a)                 # CPython: True    pxx: True
```

Two dicts with the same contents compare unequal; a dict compares equal only
to itself. Lists are already correct (`[1, 2] == [1, 2]` is True), so the
value-comparison machinery exists and the dict path simply falls through to a
pointer compare.

Silent and directly harmful: `if cfg == defaults:` is always False, and any
caching/dedup keyed on dict equality quietly does the wrong thing.

Found by the operator × operand-type sweep against CPython, in the same run
that found [[bug-nilpy-int-equals-string-segfaults]].

## Fix direction

Mirror TPyList's value comparison in TPyDict: equal length, and every key in
one present in the other with an equal value. Keys are variants, so reuse the
same element comparison the list path uses rather than writing a second one.
`!=` must follow from the same helper.

## Gate

`make test-nilpy` + self-host byte-identical, plus dict `==`/`!=` cases (equal,
different value, different key, different length, nested, self) diffed against
CPython.

## RESOLVED — `pydict_eq` in pylib, plus the arm PyVarEq was missing

Two pieces, and the second was only visible after the first:

1. **`pydict_eq(a, b: TPyDict)`** (pylib.pas), beside `pylist_eq`: same length,
   then every key of `a` looked up in `b` with an equal value. A per-key
   LOOKUP, not a parallel walk, because dict equality ignores insertion order —
   `{"a":1,"b":2}` equals `{"b":2,"a":1}`. It uses a new `PyDictIndexOfPtr`,
   which is `TPyDict.indexof` by slot POINTER: the method takes
   `const k: Variant` and immediately takes its address, so calling it from a
   walk over another dict's key storage would mean copying every key into a
   local Variant purely to have its address taken again.
   An arm in ir.inc mirrors the `pylist_eq` one, keyed on a new
   `IRNodePyDictRec`.

2. **A `TPyDict` arm in `PyVarEq`.** With only (1), `{"n": [1,2]}` compared
   correctly but `{"n": {"m": 1}}` did NOT: pydict_eq reaches its VALUES through
   PyVarEq, whose object case compared TPyList by content and everything else by
   pointer. The two are now mutually recursive, which is why pydict_eq is
   forward-declared.

Verified against CPython: equal dicts, reordered keys, different value, missing
key, different key set, different length, self, empty, list-valued,
dict-valued, three levels deep (equal and then perturbed at the innermost
level), a dict against an int / list / str / None / a None-valued variable, and
`{...} in [list of dicts]`. All match.

### Gate

`tools/gate.sh full`.

## Log
- 2026-07-29 — resolved, commit c4cbf2ea5.
