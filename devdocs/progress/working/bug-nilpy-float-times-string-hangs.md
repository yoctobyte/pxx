---
track: N
prio: 65
type: bug
---

# `2.5 * "ab"` hangs forever

```python
print(2.5 * "ab")     # CPython: TypeError    pxx: no output, never terminates
```

Killed at a 10s timeout with no output. `3 * "ab"` (int repeat) is fine; it is
the FLOAT count that hangs — presumably the repeat loop counts down a value
converted from a double and never reaches its bound.

A hang is worse than a wrong answer in one respect: an ordinary test run just
stops, with nothing to diff. This one was found only because the operator sweep
ran each program under `timeout`.

Whatever the eventual policy on mismatched operand types (see
[[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]), the repeat
count must be bounded before the loop, not trusted.

## Gate

`make test-nilpy` + self-host byte-identical, plus a regression test that runs
under a timeout.
