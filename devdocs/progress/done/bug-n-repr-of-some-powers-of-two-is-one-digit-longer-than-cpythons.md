---
track: N
prio: 30
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, the 9762-value repr differential behind bug-n-repr-of-a-double-near-the-smallest-normal-takes-minutes-on-soft-float-targets); parked, then landed after frankh-95's by-value AnsiString ownership fix 863d1cc2df
tags: [nilpy, float, repr, cpython-parity]
summary: "For 46 of 9762 sampled doubles, Nil Python's repr printed one digit more than CPython (`7.1202363472230444e-307` for CPython's `7.120236347223045e-307`, 2^-1016). All 46 are powers of two above the denormals. The text still read back correctly. At a power of two the gap below is half the gap above, so the shortest string that reads back can be the one rounded AWAY from the value. PyFloatRepr tried only the correctly rounded candidate. It now also tries the other neighbour, and only at a power of two, so every other value costs the same as before."
owner: ""
---

# repr of some powers of two is one digit longer than CPython's

```python
print(7.120236347223045e-307)   # CPython: 7.120236347223045e-307
                                # Nil Python: 7.1202363472230444e-307
```

## Cause and fix

At each length `sig`, PyFloatRepr rounds the exact decimal expansion to `sig`
digits and checks whether that string reads back. Around most doubles the
round-trip interval is symmetric, so the other `sig`-digit neighbour cannot
read back when the rounded one did not. At a power of two above the denormals,
the interval below is half as wide as the one above. There the neighbour on
the far side can be inside the interval when the rounded one is not, and it is
CPython's answer.

The fix: at a power of two, each length also tries that other neighbour. It is
the truncation if rounding went up, and otherwise the truncation rounded up.
The first version tried the neighbour at every value and made a 9762-value
run 60% slower (10.9 s to 17.4 s on x86-64) for no other change in output.
Limiting it to powers of two brought the time back to 10.1 s against 9.9 s.

This first landed as a patch that crashed in PXXAlloc. The cause was
frankh-95's defect: a by-value AnsiString parameter of a Pascal unit got no
retain in a non-Pascal program. That was fixed in 863d1cc2df.

## Measured (2026-09-29, on origin 84221ea790 plus this change)

- The 9762-value differential against CPython 3 (`print(x)` per value): 46
  lines differ with the previous compiler, and 0 with this one.
- `test/test_nilpy_float_repr_of_a_power_of_two_is_the_shortest.npy` holds
  those 46 values and a read-back check. It equals CPython on x86-64, i386,
  aarch64, riscv32, xtensa windowed and wasm32. With the previous compiler,
  all 46 value lines differ on each. The rows are x86-64, riscv32 and xtensa
  windowed, and each one fails with the previous compiler.
- `test_nilpy_float_repr_near_the_denormals_is_fast` still matches, and on
  riscv32 it ran in 3.3 s (4.5 s with the previous compiler, measured in the
  same session).
