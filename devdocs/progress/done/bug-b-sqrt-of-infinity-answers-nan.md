---
track: B
prio: 20
type: bug
blocked-by: []
summary: "`Sqrt(+Inf)` answers NaN where IEEE (and FPC, and libm) say +Inf. The Newton kernel guards negatives and zero but not infinities, so the bit-hack seed produces a NaN that every routine built on Sqrt inherits."
status: done
owner: track-b-bughunt
---

# `Sqrt` of infinity answers NaN

```pascal
program p; uses math; var inf: Double;
begin inf := 1.0/0.0; WriteLn(Sqrt(inf)); end.
{ prints ` Nan`; IEEE 754, FPC and libm all say +Inf }
```

```python
math.sqrt(float("inf"))    # CPython: inf    pxx: nan
```

Pre-existing — identical under `stable_linux_amd64/default/pinned` (v317).
Found 2026-08-15 while resolving
[[bug-n-math-pow-domain-error-raises-the-wrong-exception]], whose test had to
drop the row.

## Where

`lib/rtl/math.pas:177`. The routine opens with exactly two guards:

```pascal
if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;   { NaN }
if x = 0.0 then begin Result := 0.0; Exit; end;
```

`+Inf` passes both and reaches the bit-hack seed (`(bits shr 1) + (1023 shl 51)`)
and the Newton iteration, which cannot converge on an infinite residual and
lands on NaN. A NaN input presumably falls through the same way and should be
checked at the same time — `Sqrt(NaN)` must be NaN, which it may already be by
accident rather than by rule.

`Ln` next door has the full set (`x <> x`, `x < 0`, `x = 0`, `x > MaxDouble`),
so this is the sibling-case smell: one of a pair got the special values and the
other did not.

## Why it is worth fixing beyond the one call

Sqrt's own comment says "every RTL routine built on Sqrt inherited that error",
about a different defect — and it is just as true here. `Hypot`, `Norm`, vector
lengths and the statistics routines all reach it, so an infinite intermediate
turns into a NaN result somewhere far away rather than an infinity that keeps
propagating meaningfully.

## Gate

`Sqrt(+Inf)` = `+Inf`, `Sqrt(NaN)` = NaN, `Sqrt(-Inf)` = NaN, and the existing
`lib_math_correctly_rounded.pas` rows unchanged. Check the Single overload
(`lib/rtl/math.pas:1132`) at the same time — it is a separate body and almost
certainly has the same hole. Worth sweeping the neighbouring routines for
special values with `tools/fpc_diff_probe.sh` rather than fixing this one call.

## Resolved 2026-08-15 (Track B) — and the sweep found worse

The ticket asked for `Sqrt(+Inf)` and suggested checking NaN "at the same time",
and closed with *"worth sweeping the neighbouring routines for special values
rather than fixing this one call"*. Sweeping first was the right order: the
infinity was the least of it.

### Four defects, in ascending order of how badly they were wrong

| input | before | libm / IEEE |
| --- | --- | --- |
| `Sqrt(+Inf)` | NaN | **+Inf** — the ticket |
| `Sqrt(-0.0)` | +0.0 | **-0.0** — IEEE 754 keeps the sign |
| `Sqrt(NaN)` | NaN by accident, not by rule | NaN |
| **`Sqrt(5e-324)`** | **2.185e-157** | **2.223e-162** — five orders of magnitude out |

The denormal row is not in the ticket and is far worse than the one that is. It
is not an edge either: **every** subnormal input was wrong, and the error grew
as the input shrank.

### Cause — one cause for three of the four

```pascal
bits := PSqrtInt64(@x)^;
bits := (bits shr 1) + (Int64(1023) shl 51);   { halve the exponent FIELD }
```

The seed assumes a **normalised** double. A subnormal has exponent field 0 and
no implicit leading 1, so the seed is meaningless and eight Newton steps cannot
recover; `+Inf` has an all-ones field and Newton cannot converge on an infinite
residual. Both reached the seed because the routine guarded only `x < 0` and
`x = 0`. `Ln` next door already had the full set (`x <> x`, `x < 0`, `x = 0`,
`x > MaxDouble`) — the sibling-case smell the ticket called, confirmed.

### Fix

Guards for NaN, negative (which covers `-Inf`), zero **returning `x` so the sign
survives**, and `+Inf`, before the seed. Then a denormal is rescaled by an exact
power of two:

```pascal
if x < MIN_NORMAL then
begin
  Result := Sqrt(x * TWO_POW_106) / TWO_POW_53;   { 106 is even; both exact }
  Exit;
end;
```

Verified against libm on **20,006 random denormals: zero mismatches**, before it
was written into the RTL.

### Gate

- The table above, plus `Sqrt(-Inf)` = NaN and `Hypot(+Inf, 1)` = +Inf, which was
  NaN before and is the "every routine built on Sqrt inherited it" case the
  ticket predicted.
- A **5505-value differential against libm** — random positives across the whole
  exponent range plus 1500 denormals plus the named edges. One mismatch, at
  `DBL_MAX` only, and it is **pre-existing and unrelated** (see below).
- A separate 20,000-value random-normal differential: **zero** mismatches.
- The Single overload inherits (it widens to Double), checked.
- `make lib-test` green.

### Split out, NOT fixed here

`Sqrt` is 1 ULP low on some ordinary normal inputs — reproducibly at
`2.215827865120445e276` (pxx `1.4885657073574029e138`, libm
`...027e138`) and at `DBL_MAX`. That is the Dekker correction, not the seed, and
it is **rare**: 20,000 random normals found none, so it needs a targeted search
rather than sampling. Attempting it here made the code worse without fixing
anything — a `MAX_SAFE` rescale guard was written, measured, found to change
nothing, and reverted. Filed as
[[bug-b-sqrt-is-1-ulp-low-on-some-normal-inputs]], sibling of
[[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]].

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
