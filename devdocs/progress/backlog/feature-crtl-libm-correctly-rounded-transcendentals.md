---
prio: 40
type: feature
---

# crtl libm: correctly-rounded (or <1ulp) transcendentals — cbrt/log/pow/exp

- **Track:** B (lib/crtl/src/math.c). Tag: compat (glibc-parity outputs).
- **Opened:** 2026-07-19, from the quickjs oracle diff (wave 4): with printf
  digits now EXACT (b376), the remaining Math.* diffs vs a gcc/glibc-built
  quickjs are the crtl transcendental IMPLEMENTATIONS being 1 ulp off:
  cbrt(27), log(10), pow(2,0.5), exp(1). sqrt/sin/tan already match glibc
  exactly (sqrt is correctly rounded by construction).

## Why it matters

JS number semantics make libm results user-visible strings; test-quickjs
currently EXCLUDES these four from its byte-exact smoke. Fixing them lets
the smoke cover the whole Math surface, and every other C corpus target
inherits the accuracy.

## Shape

Bring-up impls in math.c are series/iteration based. Options per function:
- exp/log: higher-order minimax + double-double reconstruction (~1ulp
  reachable without bignum); pow via exp(y*log(x)) needs extended-precision
  log to avoid the classic pow ulp blowup — consider a dedicated pow path.
- cbrt: Newton with one double-double correction step.
Oracle: differential vs glibc over random doubles (the b376 sweep harness
shape), targeting byte-identical %.17g on the JS-visible range first.

## Done when

test-quickjs's smoke can include cbrt/log/pow/exp and stay byte-exact vs
the gcc-built oracle.
