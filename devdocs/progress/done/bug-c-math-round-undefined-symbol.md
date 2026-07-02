# C `math.h` `round()`/`trunc()` — undefined symbol at link (compiles clean, fails at load)

- **Type:** bug
- **Track:** A/B — C-extern-binds-Pascal-float bridge (`lib/crtl/src/math.c`
  doc comment) + whatever registers the bindable RTL math procs
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B probing `math.h` crtl coverage.

## Repro

```c
#include <stdio.h>
#include <math.h>
int main(void) {
    printf("%d\n", (int)(round(3.5)));
    return 0;
}
```

Compiles clean (`ok: ...`), but fails at process start:
```
symbol lookup error: .../a.out: undefined symbol: round
```

`sqrt`/`pow`/`fabs`/`floor`/`ceil`/`fmod`/`log`/`exp`/`sin`/`cos`/`atan2` all
verified working correctly in the same probe session (byte-correct results) —
`round` is the one outlier.

## Root cause (likely)

`lib/crtl/src/math.c`'s doc comment explains the bridge: a C call to
`sqrt`/`exp`/`sin`/`floor`/`ceil`/`fmod`/... binds **case-insensitively** to
the Pascal RTL's callable proc of the same name (`Sqrt`, `Floor`, etc. in
`lib/rtl/math.pas`). `Round`, however, is a **compiler intrinsic** in Pascal
(`compiler/parser.inc` ~3953-3963: `trunc`/`round` handled specially, lowered
directly to `Int64` conversion ops, nearest-even for `round`) — it is **not**
a real callable RTL proc with a linkable symbol. So `math.h`'s
`extern double round(double x);` has nothing to bind to: the C call survives
to link time as an unresolved external instead of erroring at compile time
(where the gap would be caught immediately and clearly).

`trunc` (same intrinsic-handling code path) — **confirmed equally affected**:
`(int)(trunc(3.9))` compiles clean, same `undefined symbol: trunc` at load.

## Why it matters

Silent-until-runtime failure is the sharp edge here: this compiles with `ok:`
and no warning, so a C program that calls `round()` looks fine until it's
actually run (and only then if load-time symbol resolution surfaces the
error — a statically-linked deployment might fail differently/later).

## Suggested investigation

Either (a) give `Round`/`Trunc` a real callable Pascal-RTL-visible proc
alongside the intrinsic (so the existing case-insensitive C-bind bridge picks
it up like `Sqrt`/`Floor` do), or (b) special-case `round`/`trunc` in the C
frontend to lower directly to the existing intrinsic conversion path (mirrors
how the C frontend already special-cases other builtins), or (c) at minimum
turn the unresolved-symbol case into a clear compile-time error naming the
crtl gap instead of a runtime symbol-lookup crash.

## Acceptance

- The repro above compiles and prints `4` (round-half-to-even of 3.5... check
  actual expected per this project's `Round` semantics, likely 4).
- `trunc(3.9)` compiles and prints `3`.

## Log
- 2026-07-02 — Filed by Track B. Isolated via minimal repro; rest of
  `math.h` (sqrt/pow/fabs/floor/ceil/fmod/log/exp/sin/cos/atan2) verified
  correct in the same session. No code touched — test/repro only.
- 2026-07-02 — Track A (crtl side, no compiler change needed): pure-C
  `trunc`/`round` added to lib/crtl/src/math.c alongside fabs/frexp/ldexp —
  Pascal Round/Trunc are intrinsics with no linkable symbol, so the extern
  bind had nothing to hit. C semantics implemented (round = half away from
  zero, NOT Pascal nearest-even; trunc toward zero via the (long long) cast,
  verified truncating). New gate test/cmath_round_trunc_b140.c incl.
  round(2.5)=3 / round(-2.5)=-3 and floor/ceil still binding to the RTL.
  make test green.
