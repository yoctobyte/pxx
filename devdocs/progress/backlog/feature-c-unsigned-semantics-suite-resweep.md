# Re-sweep the whole C suite for remaining unsigned-semantics gaps

- **Type:** feature (test coverage / bug hunt) — Track A (shared codegen) + C frontend
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** pattern from two just-fixed unsigned bugs
  ([[bug-c-unsigned-int-32bit-arithmetic-semantics]] v91,
  [[bug-c-unsigned-div-mod-32bit-backends]] v92). Both were the same shape:
  signedness/width silently lost. The suite was never swept *specifically* for
  unsigned correctness against a gcc oracle, so more of the same is likely.

## Why

The two fixes exposed a recurring class of defect, not a one-off:
- **x86-64**: integer ops run in 64-bit registers with no 32-bit truncation, so an
  inline `unsigned int` value keeps the wrong high bits unless masked.
- **32-bit backends (i386/arm32/riscv32)**: scalar ordinal ops were hardcoded
  signed (compares, div, mod), ignoring operand type.

Each was only caught because someone happened to write the repro. A systematic
sweep — every C operator/conversion exercised on an unsigned value with bit 31
set, diffed vs gcc on all five targets — will surface the rest in one pass instead
of one-at-a-time.

## Suspected remaining gaps (verify each vs gcc, all targets)

Each is a hypothesis to confirm/refute with a minimal repro, NOT a known bug yet.

- **Right shift `>>` of unsigned** must be LOGICAL (srl/shr/lsr), of signed must be
  ARITHMETIC (sra/asr). Check `(0x80000000u >> 1)` == 0x40000000 (not 0xC0000000)
  inline on every target. The C frontend maps `>>` to `tkIdent` (srl) already, but
  confirm it is not re-tagged signed anywhere and that 32-bit backends pick the
  right shift.
- **`unsigned char` / `unsigned short`** — C integer-promotion lifts these to
  signed `int`, but the *value* must stay in range (zero-extended on load). Check
  `unsigned char c = 200; (c * 2)` == 400, and `(unsigned char)x` truncation.
- **Mixed-width unsigned arithmetic** — `unsigned long` (tyUInt64) vs `unsigned int`
  (tyUInt32): result width/signedness, and whether the 32-bit-pair path on
  i386/arm32 keeps it unsigned (EmitBinop64 keys on tyUInt64 — verify both
  operands).
- **Unsigned comparison after a cast** — `(unsigned int)signedVar < otherUnsigned`,
  and the `==`/`!=` paths (currently sign-independent, but confirm under the new
  truncation).
- **Hex/octal literal suffix ranges** — `0xFFFFFFFFu` (tyUInt32), `0x100000000u`
  (tyUInt64), `0xFFFFFFFFFFFFFFFFu`/`UL`/`ULL`. The lexer consumes `l/L` but only
  `u/U` sets the unsigned flag; confirm `UL`/`ULL` width and that a bare large hex
  literal (no suffix) gets a sane type.
- **printf `%u` / `%x` / `%lu`** widths — does the variadic path format the right
  32 vs 64 bits for an unsigned arg (vs the just-fixed value model)?
- **Unsigned modulo in array indexing / hashing** — the hot real-world use
  (lua/sqlite). Re-run a hash-heavy snippet and diff.
- **`for` / `while` loop bounds** with an unsigned counter crossing 2^31 or
  wrapping at 0 (`for (unsigned i = n; i-- > 0;)`).

## Method

1. Author a `test/cunsigned_sweep_*.c` matrix (or one program with many checks ->
   exit-code / oracle-diff) covering the operators × {bit-31-set operand, wrap
   boundary, mixed width}.
2. Compile + run each on x86-64 (gcc oracle) and i386/arm32/aarch64/riscv32 (vs
   x86-64 oracle / gcc). The exit-code-bitmask style of `cunsigned_int_arith_b121.c`
   localises which check fails on which target.
3. For every divergence: trace to frontend (type tagging / missing truncation) vs
   backend (hardcoded signedness), fix gated so Pascal stays byte-identical, add
   the repro as a permanent guard, wire into `make test` + cross.

## Acceptance

- A committed unsigned-semantics sweep test (guarded in `make test` + all four
  cross targets) that passes on all five targets, matching gcc.
- Every divergence found is fixed (or, if genuinely out of scope, filed as its own
  Track A ticket and linked here).
- Self-host byte-identical; cross + lua green.

## Notes

- Landmines already mapped (reuse): CLexAll stores token SVal only for
  ident/string (use CAttrFlags for any new literal flag); 32-bit backends'
  scalar-ordinal paths are the usual signedness offenders; x86-64 needs explicit
  32-bit truncation since it computes in 64-bit regs. See
  [[project_c_unsigned_int_32bit_done]].
- Related: the C cross-coverage umbrella
  [[feature-c-cross-target-feature-coverage]].

## TRIAGE note (2026-06-30) — confirmed concrete gap

Probe found a real residual: C signed arithmetic right shift is wrong on x86-64 —
`int s = -2; (s >> 1)` returns a value != -1 (should be -1, arithmetic shift). So
this sweep is justified, not speculative; start here.
