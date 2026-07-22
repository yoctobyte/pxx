---
prio: 25
type: bug
---

# C float literal in the subnormal range parses to 0.0

- **Track:** C (cfront literal parsing; possibly shared with crtl strtod).
- Found 2026-07-19 during the crtl exact-printf differential sweep (the one
  residual diff in 4000 random doubles + specials vs glibc).

## Repro

```c
double d = 4.9406564584124654e-324;   /* DBL_TRUE_MIN */
/* pxx: bits 0000000000000000 (0.0); gcc: 0000000000000001 */
```

Min NORMAL (2.2250738585072014e-308) parses exactly right — only the
subnormal range collapses to zero. Compile-time conversion, not printf
(printf digits are exact since b376). Likely the literal-parse scale steps
underflow to 0 before the mantissa is applied. Related family:
[[bug-crtl-strtod-precision-cjson-floats]] (runtime strtod may share the
same path — check both). Severity low: JS/real code rarely spells subnormal
literals, and runtime arithmetic that PRODUCES subnormals is unaffected.

## 2026-07-22: FIXED (flush-to-zero); 1-ulp residual folded into the strtod ticket

StrToDoubleBits's `bexp < -1022 -> 0` early exit replaced with proper
denormalization (shift the 53-bit significand right with round-to-nearest-even,
sticky from the extraction remainder; carry lands on min normal). DBL_TRUE_MIN,
mid subnormals, and the min-normal boundary are bit-exact vs gcc; a 400-literal
random differential shows 388/400 exact, 12 within 1 ulp near the top of the
subnormal range — the same accumulated round-to-odd scaling error class the
normal range already carries for extreme exponents (the ~300-step decimal
scaling costs ~2^-52 relative). Correct rounding for those needs a big-int
scaling pass — tracked with the runtime twin
[[bug-crtl-strtod-precision-cjson-floats]]. Regression test
test/csubnormal_literal.c in make test. Benefits Pascal literals too (shared
lexer routine).
