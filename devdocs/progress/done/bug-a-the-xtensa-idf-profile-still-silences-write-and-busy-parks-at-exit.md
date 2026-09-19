---
track: A+S
prio: 45
type: bug
status: done
found: 2026-09-19
found-by: frankS
blocked-by: []
summary: "FIXED 2026-09-19. On the ESP-IDF profile xtensa used to lower Write/WriteLn -- and so a NilPy `print` -- to nothing, and to end a program in a busy park that starves FreeRTOS's idle task until the watchdogs reboot the chip and replay it. Now, as on riscv32: Write on IDF reaches builtinheap's PXXSysWrite (the libc stdout STREAM; fd 1 is not a POSIX fd under IDF), bare ESP stays silent, and the program end calls PXXIdfTaskEnd (vTaskDelete(NULL)). Guarded by test/test_esp_idf_writeln_end.pas in the test-esp-idf target on esp32c3 and esp32s3."
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

## Resolution (frankS, 2026-09-19)

Both halves, xtensa codegen only -- the runtime half was ISA-neutral as the
summary said. `IR_WRITE` stays silent only on BARE ESP; on IDF a const string
goes to `PXXSysWrite(1, data, len)` through the helper-call path, and every
other Write shape already reached the runtime. `EmitIdfTaskEndCall` is ungated
for xtensa and `IR_TERMINATE` calls it before the Halt exit and at the main
level, so the program ends with `vTaskDelete(NULL)`.

Verified: `test/test_esp_idf_writeln_end.pas`, a WriteLn-then-end program,
through `tools/esp_run.sh` on esp32s3 AND esp32c3 == the x86-64 oracle (a
reboot would replay the output and show as a diff); wired into
`make test-esp-idf`. Positive control: `ESP_RUN_PXX=<pin v412>` prints NOTHING
on esp32s3. The NilPy demo `examples/esp32/nilpy-s3` also depends on both
halves (`print`, then one boot over 40 s).

Inert until the next pin: pin v412 predates it.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
