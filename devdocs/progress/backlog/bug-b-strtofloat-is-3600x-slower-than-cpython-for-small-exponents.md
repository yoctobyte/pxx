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

## 2026-08-17 (frank3) — the stated cause is WRONG; a 2.2-3.1x fix landed; the gate is NOT met

Measured against `pinned` **v344**, `-O2`. Reproduced the ticket's numbers first
(95.6 us mid / 2657 us small / 2584 us sub), so the symptom is exactly as filed.

### The diagnosis in this ticket is wrong, and it changes the fix

> *"a 63-step bit-pattern search"*

**It is about 4 steps, not 63.** Instrumented `ExDecNearest`'s `CmpBits` with a
counter:

| class | `ExDecNearest` calls | `CmpBits` calls | per parse | longest expansion |
| --- | --- | --- | --- | --- |
| mid | 322 | 1336 | **4.1** | 53 digits |
| small | 400 | 1600 | **4.0** | 765 digits |
| subnormal | 400 | 1600 | **4.0** | 765 digits |

The search is seeded from `ExDecEstimate` and the doubling bracket converges
almost immediately — the 63-step figure would be the *unseeded* worst case, and
the seed is doing its job. So the cost is **not the number of comparisons, it is
the price of one**, and the "widen the fast path so fewer inputs reach the
search" framing is aimed at the wrong term: 4 comparisons at ~650 us each is
what 2.6 ms is made of.

### What the price of one comparison actually was

Each comparison expands a candidate double to its exact decimal via
`ExDecOfMant`, which built its digit string as:

```pascal
ds := IntToStr(buf[n - 1]);
for i := n - 2 downto 0 do
begin
  lp := IntToStr(buf[i]);
  while Length(lp) < 9 do lp := '0' + lp;   { and this, per limb }
  ds := ds + lp;                            { reallocates + recopies everything }
end;
```

That is **quadratic**: every limb reallocates and recopies the whole accumulated
prefix, and a subnormal is ~765 digits over 85 limbs. Replaced with a string
sized once and filled by index.

| class | before | after | speedup |
| --- | --- | --- | --- |
| mid-range | 95.6 us | **30.5 us** | 3.1x |
| small (~1e-310) | 2657 us | **1192 us** | 2.2x |
| subnormal (~1e-320) | 2584 us | **1166 us** | 2.2x |

The residue is the big-decimal multiply itself — for a subnormal, `exp2` is
about -1074, so ~82 rounds of `ExDecMul(buf, n, 5^13)` over a limb array growing
to ~85, i.e. ~14k 64-bit divisions per expansion, times four expansions. That is
inherent to expanding-to-exact-decimal and will not come down by tuning; it
comes down by **not doing it**, which is what Eisel-Lemire buys.

### Correctness — the part that was not negotiable

- **Round-trip sweep, 218,883 values, 0 mismatches**: every binary exponent x 8
  mantissas, the 2000 smallest subnormals one by one, 300 powers of two each
  way, the named boundaries, and 200k random finite bit patterns.
  `FloatToStrExact(x, 17)` then `StrToFloat` returns the identical bit pattern.
- **Formatter output byte-identical to before the change**: 155,884 lines
  (`FloatToStrExact` at every precision 1..17 plus `FloatToStr`, over every
  exponent and the subnormal floor) diffed against a build of the pre-change
  `sysutils.pas`. `cmp` clean. `ExDecOfMant` feeds both directions, so this was
  the check that mattered.
- `make lib-test` green.

### Landed as a gated test, because nothing guarded this

`test/lib_strtofloat_roundtrip.pas` (~2.7 s, in `make lib-test`). `lib_floattostr`
checks the FORMATTER against expected strings; the exact PARSE path had **no
test at all**, which is how a performance change here could have traded away
correct rounding silently.

It immediately earned its place by flagging `-0.0`. That turned out to be **FPC
parity, not a bug**: measured against FPC 3.2.2, `FloatToStr(-0.0)` prints `0`
there too, while `StrToFloat('-0')` returns negative zero — the formatter drops
a sign the parser preserves. pxx agrees on both halves bit for bit. (CPython
differs, `repr(-0.0)` is `-0.0`, but FPC is this RTL's oracle.) The asymmetry is
now asserted explicitly so a future one-sided "fix" breaks the test.

### This ticket's gate is NOT met — deliberately left open

> *"The mid-range and small-exponent rows above drop by at least an order of
> magnitude"*

3.1x and 2.2x are not 10x. **Eisel-Lemire remains the fix** and is now correctly
scoped by the measurement above: it wins by removing the exact expansion from
the common path entirely, not by reducing a step count that was never 63. The
quadratic string build was a real and independent defect sitting underneath it,
worth landing on its own — it also speeds up `FloatToStr` for every long
expansion — but it is not the ticket.

Moved back to `backlog/` so it can be ranked: it is not parked waiting on
anything, it is remaining work.
