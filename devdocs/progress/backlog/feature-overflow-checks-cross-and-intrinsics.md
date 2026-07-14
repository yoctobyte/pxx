---
summary: "{$Q+} follow-up: cross-backend checks (pair carry chains), Succ/Pred/Abs/Sqr, subword widths"
type: feature
prio: 35
---

# {$Q+} follow-up: cross backends + remaining checked operations

- **Type:** feature (continuation of [[feature-pascal-overflow-checks-q-plus]],
  whose x86-64 slice landed 17562666). **Track A.**
- **Status:** backlog
- **Opened:** 2026-07-15

## Remaining scope

- **Cross backends:** IR_BINOP ival=1 is currently IGNORED on
  i386/arm32/riscv32/aarch64/xtensa — {$Q+} programs run unchecked there.
  aarch64: adds/subs + b.vs (signed) / b.cs–b.cc (unsigned), mul via
  umulh/smulh compare. 32-bit pairs: carry-chain out of the hi-word
  add/sub; mul via the existing widening sequences' high half.
- **Succ/Pred/Abs/Sqr** inside {$Q+} (FPC checks them; we only tag +,-,*).
- **Subword widths:** checks currently fire at the promoted 64-bit width;
  FPC checks byte/word/longint ops at their own range. Needs the result
  width plumbed like the AN_NOT masking.
- Val() range detection (tint642's last residual) is a SEPARATE family —
  typed Val dispatch — file on pickup.

## Acceptance

- test_overflow_checks_qplus runs on all qemu targets against the x86-64
  oracle output.
- tint642 passes fully once Val lands (whichever order).
