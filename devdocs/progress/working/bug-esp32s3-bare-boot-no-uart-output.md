---
prio: 40
---

# `make test-esp-bare` — the esp32s3 (xtensa) leg emits NO UART output

- **Type:** bug (cross target — xtensa/ESP32-S3)
- **Track:** A — core (xtensa backend / ESP boot path)
- **Status:** working
- **Found by:** running `make test-esp-bare` as the cross gate for
  [[bug-pascal-exceptaddr-returns-nil]] (b340), which touches every backend's raise stub.

## Symptom
```
esp32c3 bare-boot ok (UART output == x86-64 oracle)
--- /tmp/test_esp_bare.oracle
+++ /tmp/test_esp_bare.s3
@@ -1,3 +0,0 @@
-hello esp32 bare
-12345
--42
esp32s3 bare-boot MISMATCH
```
The esp32**c3** leg (riscv32) passes. The esp32**s3** leg (xtensa) produces an
**empty** output file — not wrong output, *no* output. That shape (nothing at all,
rather than a corrupted line) points at boot/UART bring-up or the harness, not at
codegen of the three statements being printed.

## NOT a b340 regression — verified
Reproduced with a compiler built from **51968776** (the commit before the 2026-07-14
session started), so it predates b338/b339/b340. The b340 xtensa change (the raise stub
records its return address; IR_EXC_CLEAR zeroes the new slot) is not implicated: this
test does not raise, and the failure is identical without it.

Not filed as a b340 blocker for that reason — but it means the xtensa leg of the cross
gate has been giving no signal, which is worth more than the test itself.

## Where to start
- Is this environmental (missing/changed qemu-xtensa or esp32s3 machine support) or a
  real boot regression? Check whether the s3 image even reaches its entry point.
- The c3/s3 split is the useful lever: same program, same frontend, riscv32 boots and
  xtensa does not.
- Bisect the xtensa/ESP boot path; [[project_esp_bare_boot_done.md]] recorded this leg
  green when it landed, so something between then and now took it out (or the toolchain
  under it moved).

## Gate
`make test-esp-bare` green on BOTH legs (esp32c3 + esp32s3).
