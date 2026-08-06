---
summary: "SILENT: sysutils Format('%.2f') scales through Int64 — wrong last digit from |v| ~9e13 and outright garbage (-92233720368547758.-8, minus sign INSIDE the fraction) from ~9.2e16. FPC is correct throughout. Reachable at ordinary magnitudes: cents, byte counts, nanosecond timestamps"
type: bug
track: B
prio: 65
---

# `Format('%.Nf')` scales through Int64 and breaks at ordinary magnitudes

- **Type:** bug — **SILENT wrong output**, degrading to visible garbage.
  Track B (`lib/rtl/sysutils.pas`).
- **Opened:** 2026-08-06, found while checking whether the writeln float bug
  ([[bug-a-write-fixed-emits-false-digits-past-1e22]]) was Track B work. It is
  not — but this is, and it bites much earlier.

## Symptom

    Format('%.2f', [123456789012345.67])   pxx 123456789012345.68    FPC ...45.67
    Format('%.2f', [1e17])                 pxx -92233720368547758.-8 FPC 100000000000000000.00
    Format('%.2f', [1e30])                 pxx -92233720368547758.-8 FPC 1000000000000000000020000000000.00

Note the second form: a **minus sign inside the fraction**, on a positive
input. Everything from ~9.2e16 up prints that same constant string.

## Cause — `lib/rtl/sysutils.pas:2044`

```pascal
function FmtFixed(v: Double; prec: Integer): AnsiString;
var neg: Boolean; ip, scaled, k: Int64;
begin
  ...
  scaled := Trunc(v * k + 0.5);            { round half up }
  ip := scaled div k;
  fracStr := IntToStr(scaled mod k);
```

The whole value is scaled by `10^prec` into an **Int64**. Two thresholds, both
functions of `prec` (figures below are `prec = 2`, so `k = 100`):

| regime | threshold | result |
| --- | --- | --- |
| `v*k` exceeds 2^53 | `v` ≈ **9.0e13** | last digit(s) wrong — the double cannot hold the scaled value exactly |
| `v*k` exceeds 2^63 | `v` ≈ **9.2e16** | `Trunc` wraps to Int64.Min; `div k` = -92233720368547758 and `mod k` = -8, hence the `.-8` |

The first regime is the dangerous one: it is silent, and 9e13 is not an exotic
magnitude — money in cents, byte counts, and nanosecond timestamps (epoch ns is
~1.75e18 today) all pass through it.

## Not the same bug as the writeln one

[[bug-a-write-fixed-emits-false-digits-past-1e22]] is Track A, in
`compiler/builtin/builtinheap.pas`, and breaks at 1e23 by expanding the integer
part in Double arithmetic. This one is Track B, in the RTL, breaks at ~9e13,
and fails by scaling into an Int64. **Different lane, different cause,
different threshold** — they merely rhyme, and the shared symptom
(`-9223372036854775...` debris) is what the old x86-64 writeln bug also showed
before it was fixed.

For contrast, `FloatToStr(1e30)` returns `1E30` and is fine.

## Direction

`sysutils` already has exact decimal machinery — `ExDecDigits` / `ExDecRound`,
base-10^9 limbs — used by the `%g`/`%e` path. `FmtFixed` predates it and never
adopted it. Routing through that removes both thresholds at once, since the
expansion is exact integer arithmetic rather than a scaled double.

This is also a live instance of [[decide-builtin-and-library-code-sharing]],
which notes "the float core is being copied because of it": the same exact-
decimal core now exists in `lib/rtl/sysutils.pas`, `compiler/builtin/pylib.pas`
and `compiler/builtin/builtinheap.pas`, and the fixed-point paths in two of
them are wrong in two different ways.

## Gate

`Format('%.2f', ...)` matches FPC across 1e3 .. 1e30 and for
`123456789012345.67`; no `-9223372036854775` debris at any magnitude; oracle is
FPC plus `decimal.Decimal(float(x))` for the exact value.
