---
track: U
prio: 20
type: decide
---

# decide: crtl libm — correct rounding (current) vs glibc bug-parity

- **Track:** U (decision). Affected lane: B (lib/crtl).
- **Opened:** 2026-07-19, from feature-crtl-libm-correctly-rounded-transcendentals.

## The fork

That ticket's original bar was "zero diffs vs a glibc gcc build on 100k-random
sweeps". Measurement showed this is UNSATISFIABLE by any correct
implementation, because runtime glibc itself misrounds: exp ~6e-4 of random
args, log ~1e-4, pow ~9e-4, log10 ~14%, expm1 ~2.4%, cbrt ~55%(!), plus
scattered misrounds in trig/hyperbolics (all judged against 80-130-digit
decimal references; gcc's compile-time MPFR folding agrees with US, not with
its own runtime libm). Byte-parity with glibc on random inputs therefore
means reproducing glibc's error pattern bit-for-bit, i.e. porting its exact
algorithms.

## Options

1. **Correct rounding (SHIPPED, recommended).** crtl's dd kernels (b377-b385)
   are correctly rounded across the whole JS Math surface; every sweep diff
   vs glibc is a glibc error. test-quickjs's smoke covers the full surface on
   values where the oracle agrees. Cost: differential harnesses must judge
   diffs against a high-precision reference instead of assuming glibc is
   truth (tools/libm_diff_sweep.c documents this).
2. **Port ARM optimized-routines (MIT) for exp/log/pow.** glibc's own double
   exp/log/pow ARE these routines, so a faithful port gives bit-parity there;
   fetcher already vendored (tools/install_lib_candidates.sh
   optimized-routines). BUT: repo policy is "no third-party source in the
   repo" (a port with MIT attribution would be the first exception), it does
   NOT cover cbrt/log10/expm1/... (glibc's are IBM/LGPL — license-incompatible),
   and it makes crtl bit-worse than what we have.
3. **Hybrid:** keep CR, additionally maintain a "glibc-compat" diff list for
   oracle-based corpus gates. This is effectively what the smoke does now by
   value selection.

## Recommendation

Option 1. Correctness > bug-compatibility; the public claim "crtl libm is
correctly rounded where glibc is not" is strong and verifiable (claims
discipline: say "judged against high-precision references", never "matches
glibc"). Revisit only if a corpus target's oracle diff drowns in libm noise.
