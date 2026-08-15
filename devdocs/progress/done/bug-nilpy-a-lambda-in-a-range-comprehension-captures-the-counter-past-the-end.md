---
track: N
prio: 30
type: bug
commit: PENDING-COMMIT
blocked-by: []
summary: "`[lambda: k for k in range(3)]` answered 3 from every closure where CPython answers 2 — the comprehension's counter is left one past the end on normal exit, and a lambda in the body can observe it. The statement `for` was fixed for exactly this and the comprehension was reasoned to be exempt."
---

# A lambda in a range comprehension captures the counter past the end

```python
g = [lambda: k for k in range(3)]
print([f() for f in g])          # CPython [2, 2, 2]     pxx [3, 3, 3]
```

Silent. Found 2026-08-15 by a CPython differential sweep of closure and scoping
constructs. A LIST source (`for k in [10, 20, 30]`) and a STR source were
already right, which is what pins it to the range lowering rather than to
closures.

## Cause — a reasoned exemption that a capture invalidates

The statement form was fixed for this exact defect
(`bug-nilpy-for-range-counter-survives-with-the-wrong-value`): the counter is
incremented before the guard is re-tested, so on normal exit it holds the value
that FAILED the test — 3 for `range(3)`, and with a step the gap widens (9 for
`range(0, 10, 3)`, where CPython leaves 9 too only because 9 was the last value
yielded; `range(0, 12, 3)` would leave 12). The fix copies the counter into the
user's variable at the top of the body, so the variable only ever holds a value
the loop actually yielded.

That fix's own comment exempts comprehensions: *"A COMPREHENSION already loops
on a hidden name, so its variable cannot leak, and that name IS the counter with
nothing outside able to observe its terminal value."* True of a later READ,
which is what leaking means; false of a CLOSURE built inside the body, which
captures the counter itself and reads it after the loop.

The comprehension now takes the same body copy — one extra Int64 local per range
comprehension, and one fewer special case
(`devdocs/dev/normalise-dont-special-case.md`). Nothing about leaking changes:
the visible name is still the deterministic hidden one, so it neither escapes
nor clobbers an enclosing binding of the same spelling.

## Gate

`test/test_nilpy_lambda_in_range_comprehension.npy` (+`.expected`, in the
Makefile), byte-identical to CPython: the capture over a range, a list and a
str; the `k=k` default-argument idiom still pinning per iteration; a genexpr and
a dict comprehension (same lowering); a range with a start and a step; an empty
range; every ordinary comprehension form's values unchanged; and the two
non-leak rows the earlier fix installed. `gate.sh quick` GREEN. No pin — the
change is frontend-only.
