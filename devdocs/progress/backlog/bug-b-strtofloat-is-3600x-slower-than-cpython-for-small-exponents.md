---
track: B
prio: 30
type: bug
blocked-by: []
summary: "StrToFloat costs 2.6-2.9 ms per value for small-exponent input ('1.2e-320') against 0.72 us in CPython — a ~3600x gap — and 116 us even mid-range. The answer is right; the slow path is a 63-step bit-pattern search whose every step expands a candidate to its EXACT ~1080-digit decimal. Correct by construction and priced accordingly. Found timing a float differential harness, where parsing 121k values took ~60 s and the arithmetic under test took none of it."
---

# `StrToFloat` is milliseconds per value for small exponents

- **Type:** bug (performance) — **Track B** (`lib/rtl/sysutils.pas`).
- Found 2026-08-15 while timing the differential harness for
  [[bug-b-sqrt-is-1-ulp-low-on-some-normal-inputs]]: a 121,000-value sweep took
  about a minute, and isolating it showed **none** of that was the `Sqrt` under
  test. It was reading the inputs.

## Measured

5000 values per row, one `StrToFloat` each, versus CPython's `float()` on the
identical strings:

| input class | pxx | CPython | ratio |
| --- | --- | --- | --- |
| mid-range (`1..1000`) | 116 us | 0.28 us | ~410x |
| small (`~1e-310`) | 2.9 ms | 0.72 us | ~4000x |
| subnormal (`~1e-320`) | 2.6 ms | — | — |

Isolated with a parse-only program (read line, `StrToFloat`, accumulate) so no
formatting, no arithmetic and no I/O of the result is in the number. Sqrt vs
SqrtSoft timings were identical to two decimals across every class, which is
what pointed at the parser rather than the callee.

## Why it is slow, and why that is not a defect in the answer

The fast path is Clinger's: significand under 2^53 and |exponent| <= 22, one
multiply, exact. Everything else falls to `ExDecNearest`, which is a 63-step
ordered search over the IEEE bit pattern where **each step expands a candidate
double to its exact decimal expansion** and compares. For an exponent near the
denormal floor that expansion runs to ~1080 digits, so the cost is 63 x
big-decimal — milliseconds.

That design was chosen deliberately and its header says why: there is no
estimate that can be wrong by an unknown number of ULP, so the result is
correctly rounded by construction. **Do not trade that away.** The bug is that
the fast path is narrow, not that the slow path is careful.

## The fix

Widen the fast path; keep the exact search as the fallback it was meant to be.

- **Eisel-Lemire** (what CPython, Rust, Go and Abseil use) answers ~99.9% of
  real inputs with a 128-bit multiply against a power-of-ten table, and — the
  part that matters here — it *knows when it cannot decide* and defers. So it
  composes with the existing search rather than replacing it: fast path,
  Lemire, then `ExDecNearest` for the handful Lemire declines.
- Cheaper interim, if the table is unwelcome: extend the exact-multiply path
  past |expo| <= 22 using a two-step exact power (10^22 x 10^k) for the range
  where the significand stays under 2^53. Worth much less than Lemire but is
  perhaps twenty lines.

## Where it bites

Any program reading a column of scientific-notation numbers: a CSV of sensor
readings, a `.obj`/mesh file, a JSON document of floats, and every differential
test harness in this repo that feeds values on stdin. At 2.9 ms a value, a
100k-row file costs five minutes in the parser alone.

## Gate

The mid-range and small-exponent rows above drop by at least an order of
magnitude; `test/lib_floattostr.pas` and the round-trip tests stay green
byte-for-byte (correct rounding is not negotiable here); a randomised
round-trip sweep — `FloatToStrExact(x, 17)` then `StrToFloat` — returns exactly
`x` across the whole exponent range including subnormals; `make lib-test` green.
