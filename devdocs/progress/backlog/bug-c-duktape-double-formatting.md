---
prio: 55
---

# duktape: JS number formatting wrong (doubles scaled by ~5^13)

- **Type:** bug (runtime — C frontend codegen) — **Track A/C**.
- **Status:** backlog — found 2026-07-09, once the segfault was fixed (commit b30ccf88)
  and duktape actually ran JS.
- **Blocks:** [[feature-c-corpus-duktape]] running its JS test-suite (engine runs; number
  output is wrong).

## The segfault is FIXED (b30ccf88) — this ticket is the next layer
Root cause of the crash was a 32-bit pointer truncation: `ResolveNodeRec`'s AN_INDEX
branch didn't resolve the element record for an **AN_PTR_CAST base** (`((duk_tval *) x)[i]`),
so `.v.heaphdr` defaulted to a 4-byte int field → truncated + sign-extended pointer →
SIGSEGV in the first `duk_pcompile`. Fixed (regression b230). duktape now compiles + runs;
**integers, strings, arrays, JSON, closures, regex, recursion all produce correct output.**

## Symptom (remaining)
Floating-point number-to-string is wrong — digits look right but the magnitude is off by
a factor of ~5^12..5^13:

```
0.5            => 610351562.5      (= 0.5 * 5^13)
3.0            => 732421875        (= 3 * 5^12)
1.5+1.0 (=2.5) => 610351562.5      (same as 0.5 — value not distinguished!)
Math.floor(2.7)=> 659179687.4999936
String(0/0)    => -2147483648      (NaN mis-handled -> INT_MIN)
Math.sqrt(2)   => 6.369...e-37
```
`typeof 0.5` == "number" is correct, so parse/tag is fine; it is the double->string path.

## What is ruled OUT
- Field resolution: after b30ccf88 there are **0** field-resolution failures compiling
  duktape (instrumented). NOT the tval-union field access.
- `duk_double_union` bit extraction (`du.ull[0]`, `du.ui[0]`, `(ull>>52)&0x7ff`) — isolated
  test matches gcc exactly (expo=1022 for 0.5).
- Basic double union load/store `((duk_tval*)x)[i].v.d` — isolated roundtrip correct.

## Where to dig
In duktape's exact number conversion `duk_numconv_stringify` / `duk__dragon4_*` (arbitrary-
precision decimal conversion over u32 limb arrays with a tracked decimal exponent). The
~5^13 factor points at the **decimal-exponent / power-of-10 (=2·5) scaling** being off, or a
limb/shift op miscompiled. `1.5+1.0` and `0.5` giving the *same* string suggests the actual
mantissa value isn't reaching the formatter — a value/exponent variable clobbered. Attack:
- gcc oracle: instrument `duk_numconv_stringify` inputs/outputs; add the same prints, compile
  with pxx, find the first divergence.
- Suspect a 32-bit vs 64-bit or signed/unsigned mismatch in a limb/exponent computation
  (same class as the pointer bug but non-crashing), or a large-shift / union array-limb
  access in a context the isolated test didn't capture.

## Landmines
Isolated reproductions of the suspected access all pass — the trigger needs duktape's full
context (as with the pointer bug). Instrument in-place rather than trying to minimize.

[[feature-c-corpus-duktape]]

## Update — localized to numconv but not yet found (2026-07-09)
Instrumented `duk__numconv_stringify_raw`: under pxx it receives an ALREADY-WRONG value —
input `"0.5"` arrives as `x = 47683715820312.5` (= 0.5 * 5^20); `"3.0"` as `3 * 5^19`. So
the corruption is in the SHARED numconv machinery (parse over-scales by ~5^k, stringify
under-scales) — the dragon4 big-integer decimal conversion (`duk__bi_*`, `duk__dragon4_*`),
NOT downstream formatting and NOT the tval double load. Ruled out in isolation (match gcc):
the core `duk__bi_mul` primitive `(u64)a*(u64)b + acc; tmp>>32` and `1e9*1e9` u32*u32->u64.
So it is a higher-level dragon4 exponent/scale miscompile, context-dependent like the pointer
bug — needs in-place instrumentation of `duk__dragon4_prepare`/`_scale` (the power-of-2 vs
power-of-5 scaling; the 5^k factor means the ×5 path runs but the compensating ×2/shift or
the decimal-exponent `k` is dropped). Next session: bisect the dragon4 stages with prints,
gcc vs pxx, to the first divergent bigint op.

### Further localization: it's the PARSE, not stringify
Instrumented `duk__numconv_stringify_raw`: it receives an already-wrong `x` — so the JS
number LITERAL parse (`duk__numconv_parse_raw`, radix 10) produces the wrong double and it's
stored correctly (tval load/store verified). The parse accumulates the mantissa into a bigint
`f` (`f = f*radix + dig`, duktape.c ~90418) and tracks `expt`/`expt_adj`; net exponent =
`expt + expt_adj`; final value = `f * 10^net`. Next session: instrument `expt`, `expt_adj`,
and the final pushed number in `duk__numconv_parse_raw`, plus the bigint `f` after
accumulation (`DUK__BI_PRINT`), gcc vs pxx — the divergence is either the exponent counter
(a small-int off) or the bigint→double final scaling. The ~5^k (not 10^k) factor is the key
clue: the ×5 half of the ×10 scaling is applied without the compensating ×2 / decimal-point
shift.
