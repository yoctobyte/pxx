# C `unsigned int` (32-bit) arithmetic computed in 64-bit — no wraparound, signed compares

- **Type:** bug (correctness) — Track A (shared codegen) + C frontend
- **Status:** backlog
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
