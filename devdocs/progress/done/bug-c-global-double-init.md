# C: global `double`/`float` initializer stored as 0

- **Type:** bug (C frontend — Track C / data emission)
- **Status:** done
- **Found / Opened:** 2026-06-27 (Track A+C, surfaced while isolating the
  C double-value-model fixes — a `static double srcv = 3.14;` test scaffold
  read back 0, a false lead that cost time to rule out)
- **Closed:** 2026-06-27

## Symptom

A file-scope (`static`/global) floating-point variable with an initializer was
emitted as **all-zero** in the data section; the initializer value was dropped.
Integer globals initialized correctly.

```c
static double g = 3.14;
int main(void) { long b = *(long*)&g; return (b >> 56) & 0xff; }   /* -> 0, want 0x40 */

static int i = 42;
int main(void) { return i; }                                       /* -> 42 OK */
```

Live-verified 2026-06-27 on HEAD (after the double-value-model fixes): the
double global read 0, the int global read 42.

Re-verified 2026-06-27 audit: still open. Current `compiler/pascal26` compiled
the `static double g = 3.14` high-byte repro and it exited `0`; expected `0x40`.

## Cause

`ParseCGlobalVarDecl` recorded scalar integer and pointer/string global
initializers into `PendingInit`, but had no scalar float branch. The float token
already carried IEEE-754 double bits, but the initializer was skipped and the
global stayed zero.

## Fix

Scalar `float`/`double` globals with plain, `+`, or `-` float literals now record
a float pending initializer. `CompilePendingGlobalInits` replays it as an
`AN_FLOAT_LIT`, so normal assignment lowering stores double bits directly or
narrows to a 4-byte `float` slot.

## Regression

Added `test/cglobal_float_init_b91.c`, wired into `make test-core`.

It checks:

- `static double gd = 3.14` has high byte `0x40`
- `static float gf = -1.5` has high byte `0xbf`

The original high-byte repro now exits `64` (`0x40`).
