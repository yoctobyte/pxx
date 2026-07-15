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
- **Succ/Pred: DONE** (desugar tag; FPC-verified — see the Succ/Pred commit).
- **Abs/Sqr: NOT CHECKED — matching FPC.** Verified against FPC 3.2.2
  (2026-07-15): under {$Q+}, Abs(Low(Int64)) and an overflowing Sqr WRAP
  SILENTLY there (caught=0) — the ticket's original scope note was wrong,
  an implemented-and-reverted checked variant is in git history if Delphi
  parity ever wants it.
- **Subword widths: NOTHING TO DO — matching FPC.** Oracle-verified
  (2026-07-15): byte/word/cardinal ops under {$Q+} do NOT raise in FPC
  3.2.2 (b:=255; b:=b+1 wraps to 0, caught=0 — the arithmetic happens in
  the promoted width without overflowing; assignment truncation is
  range-check {$R+} territory, a separate unimplemented feature). pxx
  already behaves identically.
- **Remaining (both niche, deliberately deferred):** SIGNED checked mul on
  the 32-bit pairs; xtensa (ESP bare-metal — no exception runtime there
  anyway). {$Q+} is otherwise at FPC parity on all hosted targets.
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
