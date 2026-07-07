---
prio: 55  # auto
---

# C float (single precision): arithmetic rounding + implicit arg conversions wrong

- **Type:** bug (float semantics). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00174: `float a = 12.34 + 56.78; printf("%f\n", a);` → we print 69.120011,
  gcc prints 69.120003. Double sum stored to float must round to single
  (0x42.8A3D71...) then widen for %f; we get a different single → the
  double→float truncation at the store is off (or arithmetic done in single
  with different rounding). Note v177 lexer fix made literals exact; this is
  the float STORE path.
- 00175: `charfunc(99.0)` (double→char), `intfunc(99.0)`, `floatfunc('a')`
  (int→float), `floatfunc(98)` — implicit conversions at call sites with a
  float/char parameter. Output binary-differs (garbage char) → double arg
  passed to char/float param unconverted.

## Gate
Drop 00174.c/00175.c from test/c-conformance/pxx.skip; runner green.

## Triage note (2026-07-06)
00174: `float a = 12.34 + 56.78` prints 69.120011 vs gcc 69.120003. Float narrowing on store exists (cvtsd2ss, ir_codegen ~2626), so the error is subtler — likely the compile-time constant fold of the double sum feeding a slightly-off value into the narrow, or single-vs-double arithmetic order. Needs float-precision debugging (compare the exact 8-byte double bits of the folded RHS vs gcc). 00175 = implicit char/int/float argument conversions, separate. Focused session.

## Investigation 2026-07-07 — pinned to variadic float value, not formatting
Pinned precisely: `float a=12.34+56.78; printf("%f", a)` prints 69.120011 (wrong)
but `printf("%f",(double)a)` prints 69.120003 (correct). The STORED value is
correct (`printf("%.9g",(double)a)` = 69.1200027). So it is the IMPLICIT float
-> variadic arg that passes a corrupted value; explicit (double) cast is fine.
ODD: in one call `printf("%f %f", a, f)` with a=12.34+56.78 and f=1.5f, `a` is
wrong (69.120011) but `f` is correct (1.500000) — SAME arg path, so the corruption
is in how THIS float value is loaded/widened for the variadic push, not a blanket
missing promotion. Tried tagging the variadic float ARG tyDouble (default arg
promotion) in ir.inc call-arg lowering — did NOT fix it (reverted), so the loaded
`value` for `a` is not the correctly-widened double bits in this path. 00175 is
the same class (char/int/float default arg promotions). Needs tracing the exact
IR value for a variadic float operand (LOAD_SYM widening) vs the (double)-cast
path. Track A (ir.inc / codegen), focused session.


## RESOLVED 2026-07-07 (Track A+C, sole-A) — x86-64
Two distinct bugs, both in ir_codegen.inc SysV paths:
- 00174: a `float` through `...` was narrowed to single (cvtsd2ss) at the variadic
  call site, but C default argument promotion widens float->double. Guard the
  narrowing to NAMED single params only (i < ParamCount) → printf("%f", floatvar)
  now prints the right value (stored single bits were always correct; only the
  vararg promotion was wrong).
- 00175: double->integer conversion was entirely missing in C mode — a double
  assigned/passed to an int/char/long target bit-copied the raw double bits
  (`int x=3.7`→garbage, `long l=9.9`→raw bits, `charfunc(99.0)`→0). Added
  cvttsd2si truncation, mirroring the existing int->float cvtsi2sd, in
  IR_STORE_SYM, IR_STORE_MEM, and both IR_CALL arg-push loops (gated: float value
  into a non-SSE/integer slot; variadic floats stay double). C-mode only; Pascal
  rejects implicit float->int at parse, self-host byte-identical.
Both dropped from pxx.skip → c-conformance 198/0. Regression b176. make test +
lua green. FOLLOW-UP: cross backends (i386/arm32/aarch64/riscv32) still lack the
C double->int conversion; file if a cross float test needs it.
