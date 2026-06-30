# C `unsigned int` (32-bit) arithmetic computed in 64-bit — no wraparound, signed compares

- **Type:** bug (correctness) — Track A (shared codegen) + C frontend
- **Status:** DONE (2026-06-30, pin v91, commit 84a3fbf0)
- **Opened:** 2026-06-29
- **Found by:** empirical C-ticket re-test sweep (2026-06-29). Supersedes the
  "unsigned literal suffix `5u` tagged signed" minor note in
  [[feature-c-desktop-lua-sqlite-path]] — that note is a symptom; the real defect
  is below.

## Symptom

C `unsigned int` (32-bit) arithmetic that relies on modulo-2³² wraparound and
unsigned comparison produces wrong results when the operation is **inline** (not
first stored into an `unsigned int` variable). gcc oracle differs:

```c
unsigned int a = 5;
unsigned int d = a - 10;
printf("%u %d %d\n", d, (d > 0), (a - 10 > 0));
// pascal26: 4294967291 1 0      gcc: 4294967291 1 1
//                          ^ inline (a-10)>0 wrong
```

```c
(5u - 10 > 0)        // pascal26: 0   gcc: 1
(0u - 1) > 1000      // pascal26: 0   gcc: 1
(-1 < 1u)            // pascal26: signed cmp   gcc: unsigned cmp
```

## Root cause (traced)

Two compounding gaps:

1. **No 32-bit truncation on 32-bit unsigned arithmetic.** pxx evaluates integer
   arithmetic in 64-bit registers. `a - 10` with `a = 5` yields `-5` as a full
   64-bit value (`0xFFFFFFFFFFFFFFFB`), **not** the C-correct 32-bit
   `0xFFFFFFFB` (= 4294967291). The value is only corrected when stored into an
   `unsigned int` slot (truncates to 4 bytes) and reloaded zero-extended — which
   is why `d` (a stored var) compares right but the inline subtraction does not.
   A `tyUInt32` arithmetic result needs a 32-bit truncation (`mov eax,eax` /
   `and rax,0xFFFFFFFF`) so wraparound matches C.

2. **Equal-width comparison picks signed.** `TypeCompareUnsigned`
   (`symtab.inc:1433`) resolves "at equal width a signed operand wins" — Pascal-
   conservative. C usual-arithmetic-conversions say `unsigned int` vs `int` at
   equal rank converts the `int` to `unsigned`, so the compare is **unsigned**.
   For C-lowered comparisons the unsigned side should win at equal width. Note
   this is shared with Pascal — fixing it must NOT change Pascal semantics
   (either gate on a C-origin flag, or retype the C comparison's operands so both
   read `tyUInt32` before the call).

3. (Minor, already understood) The integer literal **`u`/`U` suffix is dropped**
   by the lexer (`clexer.inc` suffix loops just `Inc(SrcPos)`), so `5u` is typed
   `tyInteger`. Tagging it `tyUInt32` is necessary but **not sufficient** — a
   tagging-only patch was prototyped 2026-06-29 and proven observably inert
   because gaps (1)+(2) still drop the unsignedness downstream. Reverted; do the
   real fix (truncation + compare semantics) together, then re-add suffix typing.

## Acceptance

- Inline 32-bit unsigned arithmetic wraps mod 2³² and compares unsigned, matching
  gcc for the cases above.
- `u`/`U`/`UL` literal suffix typed unsigned and flows through arithmetic.
- Pascal comparison/arithmetic semantics unchanged; self-host byte-identical
  (front-end+codegen → expect a reseed) + cross green.
- Guard tests added (the repros above) under `test/`.

## Notes

Why it has not bitten lua/sqlite hard: most hot unsigned uses funnel through an
`unsigned`-typed variable (the store truncates), masking the inline gap. It is a
latent correctness bug for any inline 32-bit unsigned expression.

## Resolution (2026-06-30, pin v91, commit 84a3fbf0)

All three gaps fixed; verified vs gcc on x86-64/i386/arm32/aarch64/riscv32. Full
gate + four cross suites + lua green; self-host byte-identical (frontend changes
plus 32-bit-only backend changes — x86-64 codegen unchanged, so no reseed).

1. **Truncation (frontend, C-only).** `CMakeBinop` now wraps a tyUInt32 arithmetic
   result in `(e & $FFFFFFFF)` (`CTrunc32`, mask tagged tyInt64 so the AND runs in
   64 bits and zero-extends). Unsigned-32-domain comparisons (`CCmpUnsigned32`:
   both operands <=32-bit ordinal, at least one tyUInt32) truncate *both* operands
   so the compare runs on two non-negative values — matching C's convert-to-
   unsigned rule (`-1 < 1u` -> 0) without touching the shared `TypeCompareUnsigned`
   (Pascal stays signed-wins-at-equal-width).
2. **Suffix (lexer+parser).** `u`/`U` sets a new `CLexUnsignedSuffix` flag ->
   `CAttrFlags` bit 4 in both tokenizer storage paths (CLexAll only stored SVal for
   ident/string, so SVal-marking was dropped — that was the first attempt's miss).
   Parser tags the literal tyUInt32 (or tyUInt64 above 2^32-1).
3. **32-bit backend compares.** i386 (`EmitSetcc(op, not TypeCompareUnsigned…)`),
   arm32 (`EmitSetccArm32` gained a `signed` param: lo/ls/hi/hs for unsigned),
   riscv32 (`slt`->`sltu` when unsigned) — were hardcoded signed for scalar ordinal
   ordering compares. This was also a latent **Pascal** Cardinal/LongWord bug on
   those targets, now fixed too. aarch64/x86-64 were already correct (64-bit reg +
   the new truncation makes both operands non-negative).

Guard: `test/cunsigned_int_arith_b121.c` (six inline-unsigned checks -> exit 42),
wired into `make test` + `make test-{i386,arm32,aarch64,riscv32}`.

### Residual (separate, filed-as-note) — unsigned DIVISION/MOD on 32-bit
Out of scope here (this ticket was arithmetic-wrap + compares). The 32-bit
backends still hardcode **signed** divide/mod for scalar ordinals: i386 `idiv`
(ir_codegen386.inc ~1743), arm32 `sdiv` (ir_codegen_arm32.inc ~1323), riscv32
`div`/`rem` (ir_codegen_riscv32.inc ~955). So C `unsigned int` (and Pascal
Cardinal/LongWord) `/` and `%` on i386/arm32/riscv32 give signed results for
operands with bit 31 set. x86-64 already keys division on `TypeDivideUnsigned`.
Fix = mirror that (div->divu/udiv/`divu`+`remu`) per backend. Low-frequency
(unsigned div by a >2^31 value is rare), filed for a follow-up.
