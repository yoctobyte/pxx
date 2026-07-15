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

- **aarch64: DONE** (see the aarch64-leg commit) — adds/subs + b.vs/carry,
  smulh/umulh checked muls, cross Makefile check green under qemu.
- **i386 + arm32: add/sub DONE** (hi-word adc/sbb / adcs/sbcs flags; see
  the pair-legs commit) — checked MUL still wraps there (needs the widening
  cores' high half; Makefile pins caught=3 until it lands).
- **riscv32/i386/arm32: add/sub + UNSIGNED mul DONE** (sltu chains /
  umull high halves / pushed-operand mul probes; caught=4 Makefile-pinned
  on all five hosted targets).
- **Remaining:** SIGNED checked mul on the 32-bit pairs; xtensa ignores
  ival=1 entirely; Succ/Pred/Abs/Sqr; subword widths.
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
