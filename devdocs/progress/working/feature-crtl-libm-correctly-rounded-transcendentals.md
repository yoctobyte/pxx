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

## Log

- 2026-07-19 (fable-A, DONE — the whole JS Math surface, not just the four):
  crtl grew a double-double kernel library (~106-bit: Dekker/Knuth EFTs,
  bit-pattern constants, exact subnormal rounding via integer-quantized
  ties-to-even; crtl_dd_* in math.c) and EVERYTHING is now CORRECTLY
  ROUNDED: exp/log/pow/cbrt (b377-b380, 2c3b1406), log2/log10/expm1/log1p
  (b382, 81c28f66), sinh/cosh/tanh/asinh/acosh/atanh (b383, 43a0307e),
  hypot (b384, 5498c095), sin/cos/tan/asin/acos/atan/atan2 (b385,
  697b7a86; Cody-Waite |x|<1e8 — huge-arg Payne-Hanek split to
  [[feature-crtl-trig-payne-hanek]]).
  **KEY FINDING — the original bar was unsatisfiable:** runtime glibc
  itself misrounds (exp ~6e-4 of random args, log ~1e-4, pow ~9e-4, log10
  ~14%, cbrt ~55%!). Every sweep diff vs glibc, judged against 80-130-digit
  decimal references, was a GLIBC error; gcc's compile-time MPFR folding
  agrees with crtl. Bar reinterpreted as correct rounding — the fork is
  filed as [[decide-crtl-libm-glibc-bit-parity]] (recommend: keep CR).
  **Landmines hit:** (1) a C definition next to a case-insensitive Pascal
  twin (exp/Exp, log2, sinh, hypot, sin...) silently breaks the call
  binding — arguments never arrive; all collision names live as __crtl_*
  behind math.h function-like macros (b377). (2) crtl_dd_muld(v,-1.0)
  Dekker-splits and overflows above 2^996 (asinh/acosh NaN). (3) tiny-x
  atanh via (1+x)/(1-x) turns absolute dd error into relative — series
  branch. (4) (float) value-cast no-op fixed as b381 (cfront,
  Math.fround). printf gained glibc "-nan"/"-0" sign parity (stdio.c).
  Also filed: [[bug-c-compound-literal-address-of]] (probe crash).
  test-quickjs smoke now covers the FULL Math surface byte-exact vs the
  gcc oracle (values chosen where glibc agrees with correct rounding);
  tools/libm_diff_sweep.c carries the sweep+judge method.
