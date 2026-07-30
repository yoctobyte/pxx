---
track: N
prio: 55
type: bug
---

# `sorted()` over a list of tuples or lists dies with "expected a number, got object"

```python
print(sorted([("b", 2), ("a", 1)]))   # CPython: [('a', 1), ('b', 2)]
print(sorted([[2, "b"], [1, "a"]]))   # CPython: [[1, 'a'], [2, 'b']]
```

Both abort at run time:

```
TypeError: expected a number, got object
```

`sorted` over ints and over strings is correct, so the comparison is numeric-or-
string only and has no case for a compound element. Python's rule is
lexicographic: compare element 0, and on a tie move to element 1 — which is
also what makes `sorted(list_of_pairs)` the standard "sort by first field" idiom
and the reason this shows up so early in real code.

Exit code 219 with a message, so it is loud rather than silent — but it is a
runtime abort that no `except` can catch
([[bug-nilpy-runtime-raised-errors-bypass-try-except]]), so a program cannot
even defend against it.

Doing this properly needs the element comparison to recurse through the same
variant comparison list equality already uses — the same helper
[[bug-nilpy-dict-equality-compares-identity]] wants. Worth doing them together.

`sorted(key=...)` is a separate gap, tracked with
[[feature-nilpy-map-and-filter-over-a-lambda]].

Found by the data-structure sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus `sorted` over lists of
tuples, lists, mixed-length tuples and equal first elements, diffed against
CPython.

## Log
- 2026-07-30 — resolved, commit ba5641291.
