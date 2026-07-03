# xtensa: class instantiation (VMT + ctor) not supported

- **Type:** feature (backend parity)
- **Track:** A — `compiler/ir_codegen_xtensa.inc`
- **Status:** backlog
- **Opened:** 2026-07-03
- **Found while:** verifying docs/targets/esp32.md claims against the pinned
  compiler (Track D discovery loop).

## Problem

`TA.Create` fails with `target xtensa: class instantiation not yet supported`.
riscv32 got the full path on 2026-07-03 (alloc + VMT store + ctor call +
IR_VIRTUAL_CALL, mirroring arm32); xtensa still has the stage-1 error in its
tkGetMem branch and no IR_VIRTUAL_CALL case.

## Scope

Port the riscv32/arm32 shape: GetMem class branch (VMT via
EmitLoadDataRefXtensa + ctor call, windowed + Call0 arg conventions) and
IR_VIRTUAL_CALL ([Self] -> VMT -> slot*8, callx8/callx0).

## Acceptance

- The doc snippet (class + virtual Get) compiles for `--target=xtensa
  --esp-profile=bare` and boots correctly under `tools/esp_run_bare.sh
  --chip esp32s3` (UART-verified vs x86-64 oracle).
- docs/targets/esp32.md caveat sentence removed.

## Log
- 2026-07-03 — Filed by Track A while writing user docs.
