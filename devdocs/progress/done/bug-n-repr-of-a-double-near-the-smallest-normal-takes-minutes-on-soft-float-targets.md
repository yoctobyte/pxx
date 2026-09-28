---
track: N
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, from a board report: printing 5e-324 on an ESP32-C3 under QEMU ran until the interrupt watchdog fired)
tags: [nilpy, float, repr, riscv32, xtensa, soft-float, performance]
summary: "Nil Python's repr of a double at or below the smallest normal took seconds to minutes on soft-float riscv32 and Xtensa. repr(2.2250738585072014e-308) took 20-47 s on hosted riscv32, and 24 such values took 244 s. The exact parser's float seed flushed to zero there, so every candidate the repr tried was an unseeded exact search. The seed is now computed scaled by 2^600 and returned as a bit pattern, and repr filters candidates by av's rounding midpoints before parsing. Same 24 values: 6.6 s on riscv32. The output is unchanged."
owner: ""
---

# repr of a double near the smallest normal takes minutes on soft-float targets

```python
print("extremes:", 5e-324, 2.2250738585072014e-308)
```

On a C3 under QEMU this line ran until the watchdog fired. It looked like
`5e-324` was the culprit, but the stall is the NEXT value, because `print`
emits nothing until the whole line is formatted. On hosted riscv32
`print(5e-324)` alone takes 0.2 s, and `print(2.2250738585072014e-308)` alone
takes 20-47 s (the range is machine load). On x86-64 it takes 0.2 s.

## Cause

`PyFloatRepr` finds the shortest round-tripping string by rounding to 1..17
digits and parsing each candidate back with `PyStrToFloatDef`. The parser is
exact. It runs an ordered search over bit patterns, and each step is a
~750-digit exact expansion down here. It is seeded from a float estimate
(`sig / 10^k`), and that estimate is the only float arithmetic in the path.

A candidate such as `2.225073858507201e-308` is just below the smallest normal,
so the estimate is a denormal. Soft-float riscv32 and Xtensa flush denormals to
zero (bug-a-riscv32-softfloat-has-no-subnormals.md), so the seed was bit
pattern 0. Nothing was wrong as a result, because the seed is never trusted.
But the search then doubled its way up from 0 and bisected the whole range,
once per candidate, and the value needs all 17 candidates.

So it was slowness, not a hang: no loop fails to terminate.

## The fix (compiler/builtin/pylib.pas)

- `PyExDecEstimateBits` replaces `PyExDecEstimate` and returns the seed's BIT
  PATTERN. For a negative power of ten it scales the value up by 2^600 first,
  divides, and takes 600 off the exponent field. A denormal result is built by
  shifting the significand (hidden bit included) into place. No intermediate
  is a denormal unless D < 5e-489, where 0 is the right seed anyway.
- `PyFloatRepr` expands av and its two rounding midpoints once. It parses a
  candidate only when it lies strictly between them, or on one with av's
  mantissa even, which is `PyExDecNearest`'s own rule. The parse is still the
  proof, so the answer is still correct by construction.

## Measured (2026-09-29)

| hosted riscv32 | before | after |
|---|---|---|
| `print(5e-324)` | 0.22 s | 0.32 s |
| `print(2.2250738585072014e-308)` | 20.2 s (47 s under load) | 0.33 s |
| the 24 values of the new test | 244 s | 6.6 s |

- xtensa windowed, the 24 values: 8.5 s after.
- x86-64: 9762 doubles (random bit patterns, 500 denormals, every power of two
  and its neighbours, neighbours of the classic hard cases). The output is
  byte-identical to the previous compiler's, in 19.5 s against 3 m 45 s.
- test_nilpy_float_repr and test_nilpy_float_repr_roundtrip: unchanged, and
  equal to their expectation on x86-64, i386, arm32, aarch64, riscv32 and
  xtensa windowed.
- `test/test_nilpy_float_repr_near_the_denormals_is_fast.npy` (CPython's
  output) runs on x86-64, riscv32 and xtensa windowed under `timeout 120`.

## Not in this fix

The same 9762-value differential found 46 values where Nil Python's repr is one
digit longer than CPython's (`7.1202363472230444e-307` for
`7.120236347223045e-307`). All 46 are powers of two above the denormals, and
the previous compiler prints the same. That is a separate defect with its own
commit.
