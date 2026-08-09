---
track: B
prio: 25
type: bug
summary: "Two FPC numeric divergences in lib/rtl: Math.Floor/Ceil return Double where FPC returns Integer (and Floor64/Ceil64 are missing), and sysutils declares Currency = Double where FPC's is a fixed-point 4-decimal Int64 — so a money type cannot represent 0.10"
---

# FPC numeric compatibility: `Floor`/`Ceil` return floats, `Currency` is a `Double`

- **Type:** bug (Track B — `lib/rtl`)
- **Filed:** 2026-08-09 by Track D, found while checking claims for the docs.
- **Priority:** deliberately low. Float behaviour is not on anyone's critical
  path today; this surfaced only because fixed-point decimal came up. Raise it
  if [[idea-cobol-frontend-feasibility-costing]] or any financial-arithmetic
  work becomes real, since both items are directly in that path.
- **Owner:** —

## 1. `Math.Floor` / `Math.Ceil` return floats

```pascal
lib/rtl/math.pas:54  function Floor(x: Double): Double;
lib/rtl/math.pas:55  function Ceil(x: Double): Double;
lib/rtl/math.pas:118 function Floor(x: Single): Single;
lib/rtl/math.pas:119 function Ceil(x: Single): Single;
```

FPC's `Math.Floor` and `Math.Ceil` return **`Integer`**, with `Floor64` /
`Ceil64` returning `Int64`. Neither 64-bit variant exists here. What we have is
C's `floor()`/`ceil()` semantics wearing FPC's names.

Two visible consequences:

- `writeln(Floor(-2.7))` prints `-3.0000000000000000E+000`, not `-3`.
- `i := Floor(x)` — ordinary, correct FPC — does not compile against a `Double`
  result.

**The divergence has already propagated into our own tree**, which is the
strongest argument that it is wrong rather than a deliberate choice:

```
examples/raytracer/raytracer.pas:139   ix := Trunc(Floor(p.x));
examples/raytracer/raytracer_gui.pas:113   ix := Trunc(Floor(p.x));
```

That `Trunc(...)` wrapper exists *only* because `Floor` hands back a float. In
FPC it is plain `ix := Floor(p.x)`.

**Migration cost is small but real:** 8 call sites outside `math.pas`. Four are
`examples/mathf/mathdemo.pas`, which asserts float results (`Floor(-2.3)`
against `-3.0`) and would need its expectations changed; four are the two
raytracers, which get *simpler* (drop the `Trunc`).

For the record, the rest of the family is correct and matches FPC — verified
against the pinned compiler:

| | -2.7 | -2.5 | -1.5 | -0.5 | 2.7 |
| --- | --- | --- | --- | --- | --- |
| `Round` | | -2 | -2 | 0 | | ← banker's, correct |
| `Trunc` | -2 | | | | 2 | ← toward zero, correct |

## 2. `Currency` is a `Double`

```pascal
lib/rtl/sysutils.pas:275  { FPC Currency is a fixed-point 4-decimal Int64; this RTL models it as
lib/rtl/sysutils.pas:278    Currency = Double;
```

The comment states the divergence outright. FPC's `Currency` is a scaled
`Int64` — exactly 4 decimal places, exact addition and subtraction. Ours is
binary floating point, so the one type whose entire purpose is exact money
cannot represent `0.10`, and any monetary computation can drift from FPC's
answer.

**The substrate for a correct one already exists**, so this is less work than
it sounds: `lib/rtl/bignum.pas` (530 lines, signed add/sub/mul/compare, proven
under RSA and P-256), plus the exact decimal↔digit-string core in `sysutils`
(copied to `compiler/exdec.inc`). Nil Python already runs arbitrary-precision
integer arithmetic on that base — `2 ** 100` and `10 ** 30 // 7` are exact. A
fixed-point `Currency` is a scaled `Int64` and does not even need the bignum
path; it needs the scale-aware ops.

## Acceptance

`Floor`/`Ceil` return `Integer` with `Floor64`/`Ceil64` alongside, in-tree
callers updated, and `Currency` is a fixed-point 4-decimal `Int64` whose
add/subtract are exact. Splitting this into two tickets is reasonable if
someone takes only one half — they are filed together because they are one
theme (FPC numeric surface) found in one pass, not because they must land
together.

## Log
- 2026-08-09 — filed. Found while verifying rounding behaviour for a docs
  claim; neither is blocking anything today.
