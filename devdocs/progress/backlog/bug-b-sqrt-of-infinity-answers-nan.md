---
track: B
prio: 20
type: bug
blocked-by: []
summary: "`Sqrt(+Inf)` answers NaN where IEEE (and FPC, and libm) say +Inf. The Newton kernel guards negatives and zero but not infinities, so the bit-hack seed produces a NaN that every routine built on Sqrt inherits."
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
