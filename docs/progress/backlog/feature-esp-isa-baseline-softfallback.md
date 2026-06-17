# ESP ISA baseline + software fallbacks for older parts

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-17 (from the xtensa div/mod work)

## Baseline (current policy)

The ESP backends emit **native hardware opcodes** assuming a modern-part
baseline, matching what the Espressif gcc toolchains emit:

- **Xtensa:** ESP32-**S2/S3 (LX7)** and later. Uses the 32-bit integer
  **multiply** option (`mull`) and the 32-bit integer **divide** option
  (`quos`/`quou`/`rems`/`remu`), plus SAR-based shifts (`ssl`/`sll`,
  `ssr`/`srl`). These are the user's actual boards.
- **RISC-V:** ESP32-**C3** and later (RV32IMC). Uses the **M** extension
  (`mul`/`div`/`rem`) — already the case in `ir_codegen_riscv32.inc`.

The user's hardware is S2/S3 + C-series, so native is correct, smallest, and
fastest — not a shortcut. Encodings: shifts/M-extension verified with
`llvm-mc`; the xtensa divide mnemonics are absent from llvm-mc 18, so
`quos/quou/rems/remu` were taken from `xtensa-esp32s3-elf-as` + objdump (RRR
layout identical to `mull`, only byte2 differs: D2/C2/F2/E2).

## Deferred: older parts without the option

**ESP32 classic (LX6)** has the multiply option but **not** the divide
option; some smaller cores may lack multiply too. Running PXX-emitted code
that uses `quos`/`rems` on such a part faults with an illegal/unimplemented
instruction.

When we want to support those parts, add **software fallbacks** selected by a
target-revision flag (e.g. `--xtensa-cpu=lx6`):

- `__pxx_divsi3` / `__pxx_modsi3` (and unsigned forms): restoring shift-subtract
  division built from already-verified instructions (add/sub/shift/branch).
  Either inlined at each `div`/`mod` site or emitted once as a runtime helper
  (helper form depends on the xtensa windowed-call path being solid — see the
  windowed nested-call crash found by the esp harness).
- Same shape if a no-multiply part ever matters (`__pxx_mulsi3`).

## Acceptance

- A `--xtensa-cpu=lx6` (or equivalent) profile compiles a div/mod program with
  no `quos`/`rems` in the image (readelf/objdump check) and produces the same
  output as the LX7 native build under emulation.

## Notes

- Right now the goal is **complete feature implementation** on the modern
  baseline; opcode-availability tuning for older parts is explicitly a later
  pass. This ticket just parks the decision so the baseline assumption is
  documented rather than implicit.
- Native xtensa div/mod landed 2026-06-17 (commit 54bc954).
