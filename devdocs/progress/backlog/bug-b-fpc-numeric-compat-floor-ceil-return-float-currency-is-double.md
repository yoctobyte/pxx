---
track: B
prio: 25
type: bug
blocked-by: idea-cobol-frontend-feasibility-costing
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

## Half 1 DONE 2026-08-09 (Track B): Floor/Ceil return Integer

`Floor`/`Ceil` return `Integer` and `Floor64`/`Ceil64` return `Int64`, matching
FPC — verified against an FPC build: `Floor(-2.7) = -3`, `Ceil(-2.7) = -2`,
`Floor(2.7) = 2`, `Ceil(2.7) = 3`. Single overloads return `Integer` too, as
FPC's do.

All 12 in-tree call sites updated, and the ticket's own evidence held up: the
raytracers got SIMPLER. `ix := Trunc(Floor(p.x))` is now `ix := Floor(p.x)`,
which is what the same line says in FPC. `examples/mathf/mathdemo.pas` gained a
`ChkI` integer comparator for its four assertions.

**Two hazards worth recording, because neither is obvious:**

1. **An internal caller would have silently overflowed.** `DdRint` — the
   ties-to-even helper under the double-double kernel — floors values up to
   2^52. With `Floor` returning a 32-bit `Integer`, everything between 2^31 and
   2^52 would have wrapped, in a function whose whole job is exact rounding. It
   now uses `Int()` directly, which is what it always meant (its operand is
   non-negative, so the two agree). This is exactly why FPC ships the 64-bit
   pair, and the new test pins `Floor64` past 2^31 in both signs.

2. **`floor`/`ceil` are C names, and the return type was the only thing making a
   collision invisible.** Before, Pascal `Floor(Double): Double` and C
   `floor(double): double` had identical signatures, so a hijack would have been
   undetectable; afterwards it would be loudly wrong. Measured before committing
   — with a deliberately broken Pascal `Floor` returning 0, C's `floor` still
   gave gcc's answer, so C resolves to crtl's. `test/cmath_no_pascal_hijack.c`
   keeps watching (bug-c-pascal-math-names-hijack-libc-through-pxxcio).

## Half 2 (`Currency = Double`) — NOT done, and deliberately deferred

Left as filed, with `blocked-by` pointing at the COBOL costing ticket, because
that is where the requirement actually lives. Reasons not to do it now:

- **It is the same theme as a live design discussion** — fixed-point decimal,
  rounding modes and COBOL — and [[idea-cobol-frontend-feasibility-costing]]
  already says what is missing is narrower than "a decimal type": scale-aware
  add/sub/mul/div with the standard's rounding modes. Building a
  4-decimal `Int64` `Currency` in isolation risks being the wrong shape for the
  thing that will actually consume it.
- **The blast radius is not where it looks.** Only 6 in-tree `Currency`
  references outside `sysutils`, so the type change is small — but `Currency`
  currently rides every `Double` path (`FloatToStr`, `FormatFloat`, `StrToCurr`,
  `writeln`), and a scaled `Int64` needs its own formatting and parsing that
  agrees with FPC's 4-decimal output. That is the real work, and it belongs with
  the decimal arithmetic rather than ahead of it.

This ticket's own text agrees splitting is reasonable; half 1 stands alone and
is done.

