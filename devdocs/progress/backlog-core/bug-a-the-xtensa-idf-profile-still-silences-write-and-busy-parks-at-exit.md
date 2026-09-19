---
track: A+S
prio: 45
type: bug
status: open
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "On the ESP-IDF profile, xtensa still (a) lowers Write/WriteLn -- and so a NilPy `print` -- to NOTHING (ir_codegen_xtensa.inc's IR_WRITE PLATFORM_ESP arm), and (b) ends a program in a busy `j 0` park (emit.inc EmitExit/EmitExitReg), which starves FreeRTOS's idle task until the task and interrupt watchdogs reboot the chip and replay the program. riscv32 had both and both were fixed on 2026-09-19: IR_WRITE on IDF routes through builtinheap's PXXSysWrite, whose PXX_IDF_STDIO arm goes to the libc stdout STREAM (putchar -- fd 1 is NOT a POSIX fd under IDF, measured), and the program end calls PXXIdfTaskEnd (vTaskDelete(NULL)) via EmitIdfTaskEndCall, which is gated to riscv32 because nothing could verify xtensa. The runtime half is ISA-neutral already; what xtensa needs is the codegen half: its IR_WRITE ESP arm taking the helper path on IDF (bare keeps silence), and EmitIdfTaskEndCall ungated for it. Verify with a Pascal program that WriteLns and ENDS, through tools/esp_run.sh --chip esp32s3."
---

# The xtensa IDF profile still silences Write and busy-parks at exit

The riscv32 half was done while making a NilPy application run on an
ESP32-C3 (`examples/esp32/nilpy-c3`,
`bug-a-nilpy-on-cross-targets-four-remaining-walls`). See the comments at
`EmitIdfTaskEndCall` (symtab.inc), riscv32's `IR_WRITE` arm and builtinheap's
`PXX_IDF_STDIO` block for the measurements.

Two facts that are easy to get wrong here, both measured under gdb on the C3:

- `write(1, ...)` answers EBADF under IDF. esp_libc's picolibc init opens the
  console and keeps WHATEVER fd `open()` returned in its stdin/stdout streams.
- `fflush(NULL)` load-faults in this picolibc (`__flockfile` on the NULL
  stream). stdout is line-buffered, so a newline flushes; a final line with no
  newline stays in the buffer when the task ends. That residual applies to
  both ISAs.

The existing Pascal IDF examples never hit either: they print with
`esp_rom_printf` and park politely with a `vTaskDelay` loop, which is why
neither defect showed up in `test-esp-idf`.
