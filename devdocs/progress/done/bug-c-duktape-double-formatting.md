---
prio: 55
---

# duktape: JS number formatting wrong (doubles scaled by ~5^13)

- **Type:** bug (runtime — C frontend codegen) — **Track A/C**.
- **Status:** done
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

## ROOT CAUSE FOUND + FIXED (2026-07-10) — C struct fields were case-INSENSITIVE
Not a float/dragon4 bug at all. `duk__numconv_stringify_ctx` has two adjacent
`duk_small_int_t` fields differing only in case: `b` (input radix) and `B` (output
radix). The C frontend's field lookup (`FindUField`, compiler/symtab.inc) folded
case (Pascal heritage — `ULower` + `UNameMatch`), so `b` and `B` collapsed onto the
SAME field. `nc_ctx->b = radix (10); nc_ctx->B = 2;` → both writes hit one slot, so
`b` read back as 2 instead of 10. dragon4_prepare then built `s = b^(-e)*2` with b=2
instead of 10, scaling every double by ~5^k. (The parse-vs-stringify "over/under
scale" split was the same collision seen from both directions.)

**Instrumented diff (input `String(0.5)`), gcc vs pxx:**
```
gcc: HUNT[s2n] prepare e=-20 b=10 B=2
pxx: HUNT[s2n] prepare e=-20 b=2  B=2   <- b took B's value
```
`f` and `e` were byte-identical; only `b` diverged. Minimal repro:
`struct S{int b;int B;}; s.b=10; s.B=2;` → pxx printed `b=2 B=2`, gcc `b=10 B=2`.

**Fix:** per-UClass `UClsCaseSensFields` flag (defs.inc), default False (Pascal records
stay case-insensitive). `AddUClass` inits it False; cparser sets it True at every C
struct/union creation (6 sites). `FindUField` uses a new exact matcher `UNameMatchCS`
when the owning class flags case-sensitive fields. Regression test
`test/cstruct_field_case_sensitive_b231.c` (exit 42). Self-host byte-identical,
`make test-c-conformance` 220/220, quick tier GREEN.

**Result:** `1/3 => 0.3333333333333333`, `(0.1+0.2) => 0.30000000000000004`,
`5.5%2 => 1.5`, `sqrt(2) => 1.414...`, `bigint sum => 4999950000` — all correct now.

### Residual #1 FIXED (2026-07-10) — NaN compare ignored unordered (PF)
`String(0/0)` → `-2147483648` was NOT a NaN-detection bug in duktape — it was the
x86-64 float compare in `ir_codegen.inc`: `ucomisd` + plain `setcc` read only ZF/CF
and ignored **PF (parity = unordered)**. On NaN, ucomisd sets ZF=PF=CF=1, so
`sete`/`setb`/`setbe` returned 1 and `setne` returned 0 → `NaN==NaN` true,
`NaN!=NaN` false, `NaN<x` true. duktape's `DUK_ISNAN(x)` = `(x!=x)` therefore
returned false → NaN escaped into dragon4 → `cvttsd2si` → INT_MIN. Pure-C repro
(no duktape): `d/d` with d=0 → `nan==nan`=1, `nan!=nan`=0, `nan<1`=1 (all wrong).
**Fix:** fold PF into `==,!=,<,<=` (`Eq=ZF&!PF`, `Neq=!ZF|PF`, `Lt=CF&!PF`,
`Le=(CF|ZF)&!PF`); `>`/`>=` (seta/setae, CF=0-based) already give 0 on unordered.
Now `String(0/0)`="NaN", `isNaN(0/0)`=true, `NaN!==NaN`=true. Regression b232.
Affects Pascal too (shared codegen). Self-host byte-identical (2-step reseed).

### Cross-target non-uniformity (SAME bug class) — ALL FIXED (2026-07-10)
The unordered handling differed per target (user-flagged). Verified via
`test/cfloat_nan_compare_b232.c` cross-compiled + run under qemu:
- **x86-64**: `ucomisd`+setcc, PF ignored → FIXED (fold PF, commit prior).
- **i386** (`ir_codegen386.inc:1879`): same PF gap; now calls shared
  `EmitSetccFloat` (PF-folded, raw bytes valid 32/64). FIXED, qemu 42.
- **aarch64** (`ir_codegen_aarch64.inc:1309`): `fcmp` unordered = N0 Z0 C1 V1;
  `lt`/`le` fired on NaN. New `EmitSetccA64Float` uses `mi`/`ls`. FIXED, qemu 42.
- **arm32** (`ir_codegen_arm32.inc:1472`): same VFP NZCV; new `EmitSetccArm32Float`
  uses `movmi`/`movls`. FIXED, qemu 42.
- Also switched x64 **Variant** double compare (`comisd`) to `EmitSetccFloat`.
- **riscv32 / xtensa**: already NaN-correct (soft-float kernel returns code 2 =
  unordered); verified riscv32 qemu 42. No change.

### Residual #2 FIXED (2026-07-10, Track B) — RTL Sqrt/Ln domain errors
`Math.sqrt(-1)` → `0` was RTL `Sqrt` (lib/rtl/math.pas), which C `sqrt` binds to
case-insensitively. `Sqrt` returned 0 for `x<=0`; FPC-faithful IEEE is NaN for
`x<0`, 0 for x=0. Sibling `Ln` had the same gap (`x<=0`→0; correct is `Ln(0)=-Inf`,
`Ln(<0)=NaN`). Fixed both: produce NaN via `z/z` and -Inf via `-1.0/z` (z=0 var, no
NaN literal, no const-fold). Verified under PXX_STABLE (pinned) via bits: sqrt(-1)
NaN, sqrt(0)=0, log(-1) NaN, log(0)=-Inf. duktape `Math.sqrt(-1)` now "NaN".
Regression `test/cmath_domain_nan_b233.c`. lib-test green. Existing callers
(pow/cbrt/acosh/…) guard positive, so no regression.

### Residual #3 (open) — sqrt last digit
`Math.sqrt(2)` → `1.414213562373095` vs gcc `1.4142135623730951` — pxx drops the
17th sig digit (rounds to a different double). Distinct shortest-round-trip issue in
the free-format dragon4 generate path.

### Further localization: it's the PARSE, not stringify (superseded by ROOT CAUSE above)
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

### Residual #3 FIXED (2026-07-10) — RTL Sqrt now correctly-rounded
`Math.sqrt(2)` → `1.414213562373095` (dropped 17th digit) was NOT a dragon4
generate bug: pxx's `sqrt(2)` double was itself 1 ULP low (`...bcc` vs IEEE
`...bcd`), so dragon4 correctly formatted a slightly-wrong value. Root cause: RTL
`Sqrt` (lib/rtl/math.pas) was software Newton-Raphson whose FP fixed point sits 1
ULP below the correctly-rounded root; the `g:=x` seed + 200-iter cap also never
converged for large/small exponents (sqrt(1e300) wrong, near-DBL_MAX → NaN).
Fixed portably (commit 00a363e9): bit-hack exponent-halving seed → quadratic
convergence in ≤8 steps, then one correctly-rounded correction using an exact
Dekker two-product residual (`g + (x-g*g)/(2g)`). Bit-exact vs gcc on
19989/20000 random doubles (3 misses = 1 ULP at the subnormal boundary);
sqrt(2) bit-exact on all 5 targets. Regression b240.

**All residuals now closed — resolving the ticket.**

## Log
- 2026-07-10 — resolved, commit 00a363e9.
