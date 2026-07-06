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
