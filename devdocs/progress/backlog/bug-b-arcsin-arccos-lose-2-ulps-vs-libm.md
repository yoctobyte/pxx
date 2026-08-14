---
track: B
prio: 20
type: bug
summary: "ArcSin/ArcCos in lib/rtl/math.pas are 1-2 ulps off libm for mid-range arguments (asin(0.5) answers ...982991 where libm and CPython say ...982989); ArcTan agrees exactly"
---

# `ArcSin` / `ArcCos` lose up to 2 ulps

- **Type:** bug (accuracy) — **Track B** (`lib/rtl/math.pas`)
- **Found:** 2026-08-15, wiring `math.asin`/`acos`/`atan` for NilPy
  ([[bug-nilpy-math-surface-remaining-gaps-and-degrees-association]]). The
  NAMES now resolve; this is what the values then showed.

```
             pxx                  CPython / libm
asin(0.5)    0.5235987755982991   0.5235987755982989
acos(0.5)    1.0471975511965974   1.0471975511965979
atan(2.0)    1.1071487177940904   1.1071487177940904   <- exact
asin(0)      0.0                  0.0                  <- exact
acos(1)      0.0                  0.0                  <- exact
```

So the endpoints and the whole of `ArcTan` are right, and the error appears
for mid-range arguments — which points at the identity used to build asin/acos
on top of arctan (`asin(x) = atan(x / sqrt(1 - x²))` and its acos sibling)
rather than at `ArcTan` itself. That form loses bits twice: in `1 - x²` for x
near ±1, and in the division.

Low priority by the standing rule that float-accuracy work is mechanical and
cheap to defer — filed so the measurement is not lost, not because anything is
blocked on it. `lib/rtl/math.pas` already carries a correctly-rounded `Sqrt`
(with a Dekker two-product correction), so the file's own bar is higher than
this.

## Gate

`test/lib_math_correctly_rounded.pas` extended with asin/acos across
[-1, 1] against a reference table, and the NilPy row re-diffed:
`math.asin(0.5)` / `math.acos(0.5)` matching CPython exactly. The NilPy test
`test/test_nilpy_math_surface_and_random.npy` deliberately asserts only the
exact cases today; add the mid-range ones when this lands.
