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
