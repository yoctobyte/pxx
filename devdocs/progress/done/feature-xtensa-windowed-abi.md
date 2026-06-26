# Xtensa windowed ABI codegen variant (for ESP-IDF interop)

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Unblocks:** feature-esp32-idf-xtensa
- **Opened:** 2026-06-12 (esp32-idf integration plan)

## Motivation

ESP-IDF builds all Xtensa code with the **windowed ABI** (`entry`/`retw`/
`call8`); our stage-1 backend is Call0. Mixing breaks in the IDF→PXX
direction: `call8 app_main` rotates the register window and a Call0 callee
looks for its return address in the wrong register. For S2/S3 (the user's
actual boards) PXX must emit windowed code in the idf profile.

The change is contained because window rotation preserves our register
view: caller marshals args into a10–a15, hardware rotates by 8 on `call8`,
and the callee still sees them in **a2–a7** — same as Call0 today. FreeRTOS
installs the window overflow/underflow handlers; we never touch them.

## Scope

- Profile flag (e.g. `--xtensa-abi=windowed`, default for the idf profile;
  Call0 stays for bare).
- Encoder additions in `compiler/xtensaenc.inc`: `entry sp, imm12`
  (imm scaled ×8), `retw.n`, `call8`, and `callx8`. Encodings were verified
  against Espressif `xtensa-esp32s3-elf-as`/`objdump`.
- Prologue: `entry a1, 32` replaces the manual a0/a15 save; the existing
  local-frame adjustment remains separate. `a15` is only a bootstrap base
  while parameters are spilled; body frame references use `a7` so calls through
  `call8` cannot clobber the frame base.
- Epilogue: `retw` (result already in a2 = caller's a10).
- Call site: args to a10–a15 (≤6 args), `call8` direct / `callx8` via
  literal-loaded address for imported symbols; read result from a10.
- `EmitCallProc`/`ApplyCallFixups` call8 offset encoding mirrors call0
  (same 18-bit word-offset CALL format, n=2).

## Non-goals

- No call0↔windowed thunking. The profile picks one ABI for the whole
  object; imported IDF code is always windowed.
- No >6 args (matches stage-1 limit).
- No alloca/variable frames.

## Acceptance

- Smoke program (procs, params, results, loops — the esp32_smoke.pas oracle)
  compiles in windowed mode; every instruction stream cross-checks clean
  against llvm-mc reference encodings.
- Window-correctness can't be fully proven under qemu-user dc232b without
  handler setup — final proof is the linked IDF boot in
  feature-esp32-idf-xtensa. Encoding-level + structural verification is the
  bar here.

## Notes

- ESP32 LX6/LX7: 64 physical ARs, window increment 8 for call8.
- `entry` requires frame size ≤ 32KB (imm12×8) — fine.
- PXX `not` is not bitwise-int (see done/feature-target-esp32 log) — keep
  using div/mul for masks in new encoder math.

## Log

- 2026-06-12 — Implemented `--xtensa-abi=windowed`: `entry`, `retw.n`,
  `call8`, `callx8`, argument marshalling through caller `a10..a15`, return
  copy-back from `a10`, and windowed direct-call fixups. `make test-emit-obj`
  now covers xtensa Call0 and windowed objects, including an
  `xtensa-esp32s3-elf-gcc` link check when the toolchain is installed.
  Commit: pending.
