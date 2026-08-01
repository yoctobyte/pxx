---
track: B
prio: 65
type: bug
---

# `FloatToStrSig` caps at 15 significant digits, so no double round-trips

- **Type:** bug / missing capability (RTL) — **Track B** (`lib/rtl/sysutils.pas`)
- **Found:** 2026-08-01, blocking
  [[bug-nilpy-float-repr-not-shortest-roundtrip]].

## The cap

`lib/rtl/sysutils.pas:921`:

```pascal
if sig > 15 then sig := 15;      { past 15 a double scaled in doubles lies }
```

The comment is honest about why: the routine normalises the mantissa by
multiplying/dividing in DOUBLES, so past ~15 significant digits the scaling
itself introduces error and the extra digits would be fiction. Given that
algorithm, capping is the right call — the cap is not the mistake, the
algorithm's reach is the limitation.

## Why it needs lifting

An IEEE-754 double needs **up to 17 significant digits** to round-trip. At 15,
some values simply cannot be printed and re-read to the same bits. Measured with
a 1..17 round-trip probe (`StrToFloat(FloatToStrSig(d, p)) = d`):

| value | shortest p that round-trips | `FloatToStrSig(d, 17)` |
| --- | --- | --- |
| `25.4` | 3 | `25.4` |
| `0.1` | 1 | `0.1` |
| `0.1 + 0.2` | **never** | `0.3` |
| `1.0/3.0` | **never** | `0.333333333333333` |
| `2.834645669291339` | **never** | `2.83464566929134` |

So `FloatToStr` cannot be the basis of any exact float output, and anything
needing a faithful decimal form of a double is blocked.

## Fix shape

Exact decimal digit generation, which means NOT scaling in doubles:

- integer/bignum arithmetic over the 53-bit mantissa and binary exponent (the
  classic exact approach — this repo already has bignum machinery, e.g. the
  promotable-int path that computes 25! exactly), or
- a Grisu/Ryu-style shortest-representation algorithm.

Either gives correct digits to 17 and makes shortest-round-trip possible.

**Keep `FloatToStr`'s existing output contract unchanged** unless deliberately
changed: it is the shared Pascal path, so its formatting is observable by every
Pascal program and by test expectations across the tree. The safe shape is a new
exact entry point (and lifting the cap inside `FloatToStrSig` only once the
digits past 15 are real), not a behaviour change in place.

## Other spellings noticed while probing (same routine)

Not necessarily bugs for Pascal — recorded because the NilPy side has to
reconcile them:

| input | `FloatToStrSig` | Python `repr` |
| --- | --- | --- |
| `5.0` | `5` | `5.0` |
| `1.0e20` | `1E20` | `1e+20` |
| `-0.0` | `0` | `-0.0` |
| NaN / Inf | `NaN` / `Inf` | `nan` / `inf` |

## Gate

A round-trip test over a spread of doubles — including `0.1+0.2`, `1/3`,
denormals, very large/small magnitudes, and negative zero — where
`StrToFloat(exact_repr(d)) = d` for every case, and Pascal's own `writeln` of a
Double is byte-unchanged.
