---
track: N
prio: 70
type: bug
---

# `str()` of a float whose integer part exceeds Int64 writes garbage bytes

```python
print(1e19)     # CPython: 1e+19    pxx: 9223372036854775809.o72036854775808
print(1e300)    # CPython: 1e+300   pxx: 9223372036854775809.o72036854775808
```

The output is not merely mis-formatted: it contains a literal `o` where a digit
belongs, and the digits after the point are a fragment of the saturated Int64
(`9223372036854775808`) that precedes them. That is a buffer being written past
its end / read back unterminated, in the float→string path — a memory bug that
happens to surface as text.

It is reachable from ordinary arithmetic, not just from a literal: `3 / 0`
yields the same string (see
[[bug-nilpy-division-by-zero-is-not-catchable]]), so any program that divides
by zero prints corrupted bytes to stdout.

The conversion clearly saturates the integer part at `High(Int64)` and then
formats the remainder from the same buffer. It needs the large-magnitude case
handled properly instead — which is also the point at which CPython switches to
exponent form.

## Two more float-formatting divergences from the same sweep

Lower severity — no memory involved, but they make NilPy output differ from the
oracle on ordinary values:

| expression | CPython | pxx |
| --- | --- | --- |
| `1.5e18` | `1.5e+18` | `1500000000000000000.0` |
| `123456789012345678.0` | `1.2345678901234568e+17` | `123456789012345680.0` |
| `0.1 + 0.2` | `0.30000000000000004` | `0.3` |
| `"%e" % 3.14159` | `3.141590e+00` | `3.141590` |

(`%e` was the ONLY divergence in a 21-case sweep of f-strings, `%`-formatting
and `.format()` — everything else matched CPython exactly, so it is a
one-conversion gap, not a formatting-engine problem.)

CPython's `repr` is the SHORTEST string that round-trips, in exponent form
outside `1e-4 .. 1e16`. pxx prints a fixed-point form with fewer digits, so
`0.1 + 0.2 == 0.3` is False while the printed forms are equal — the classic
confusing-output case. Whether to match CPython exactly here is worth deciding
once (it affects every printed float); the garbage-byte case above is a bug
regardless.

## Gate

`make test-nilpy` + self-host byte-identical, plus a float-printing regression
table diffed against CPython.
