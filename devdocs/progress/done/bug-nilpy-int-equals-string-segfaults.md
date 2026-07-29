---
track: N
prio: 80
type: bug
---

# `3 == "ab"` SEGFAULTS

```python
print(3 == "ab")      # CPython: False        pxx: SIGSEGV
```

One line, no imports, no classes. `!=` crashes the same way. Comparing an int
with a str is ordinary, legal Python — `x == "done"` where `x` happens to hold
a number is exactly the shape a real program hits — so this is a crash on
valid input, not a laxity question.

The comparison presumably lowers to a string compare with the int's VALUE used
as a string handle, i.e. it dereferences 3 as a pointer.

Found by sweeping every binary OPERATOR against every operand-type pair and
diffing against CPython (see [[feedback_sweep_operators_against_oracle_not_just_features]]);
`op_eq` and `op_ne` were the only two of twenty that dumped core.

## Related, from the same sweep — file/fix separately

- [[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]
- [[bug-nilpy-float-times-string-hangs]]
- [[bug-nilpy-division-by-zero-is-not-catchable]]
- [[bug-nilpy-large-float-str-overruns-into-garbage]]

## Gate

`make test-nilpy` + self-host byte-identical, plus a regression test covering
`==`/`!=`/`<`/`>` across int, float, str, list, dict and None operands.

## Log
- 2026-07-29 — resolved, commit 9b4b9d36c.
