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
