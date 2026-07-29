---
track: N
prio: 70
type: bug
---

# `zip(list, str)` yields nothing — and segfaults if any loop ran before it

```python
x = [10, 20, 30]
s = "abc"
for v in x:            # <- ANY preceding for-loop
    print("l", v)
for a, b in zip(x, s):
    print("z", a, b)   # CPython: z 10 a / z 20 b / z 30 c
```

pxx prints the three `l` lines and then SIGSEGVs.

Without the preceding loop the same zip does not crash — it silently produces
NO iterations at all, and execution continues:

```python
x = [10, 20, 30]
s = "abc"
for a, b in zip(x, s):
    print("z", a, b)   # pxx: nothing
print("after")         # pxx: after
```

`zip(list, list)` is correct in both shapes, and iterating a string on its own
(`for c in s`) is correct, so it is specifically a STRING as a zip operand.
The silent-empty form is the more dangerous of the two: a zip that produces no
pairs looks like empty input rather than like a bug.

Found while sweeping iteration constructs (for over list/dict/str, enumerate,
zip, range with step and negative step, list/dict comprehensions, break,
continue) against CPython — everything else in that sweep matched exactly.

Measured with the compiler at 33db0107d.

## Gate

`make test-nilpy` + self-host byte-identical, plus zip over every operand pair
of (list, str, dict, range) — with and without a preceding loop, since the
preceding loop is what turns the silent case into the crash.
