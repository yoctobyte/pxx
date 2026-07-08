---
prio: 35
---

# C conformance / feature coverage on ESP (xtensa + ESP32-C3 riscv32 bare)

- **Type:** feature (test coverage). Track C (+ A for backend gaps found).
- **Split 2026-07-08** out of [[feature-c-cross-target-feature-coverage]]: the
  desktop matrix (i386/aarch64/arm32/riscv32 QEMU) landed as
  `make test-c-conformance-cross` + `test-lua-cross`; the ESP bare/QEMU leg
  needs its own harness plumbing and stays open here.

## Scope
- Pick the c-testsuite subset that makes sense bare-metal (no
  files/argv/stdout contract → needs the esp harness's UART capture, see
  `tools/esp_run_bare.sh`) or route through the hosted-riscv32 ESP-C3 path.
- Wire a make target analogous to `test-c-conformance-<arch>` with an
  explicit per-target skip file; file per-gap Track A tickets.

## Notes
- ESP C entry stub status unknown — desktop targets got theirs in the
  2026-06-29 arc; xtensa/ESP may still raise "C program entry stub not
  implemented for this target yet". First step is a bare
  `int main(void){return 42;}` probe on the esp harness.
