# PXX → ESP-IDF esptimer demo (ESP32-C3)

Slice 1 of the ESP peripheral callback API
(`feature-esp-peripheral-callback-api`): a periodic timer callback through the
`esptimer` unit's event surface — the app assigns `t.OnElapsed := @OnTick` and
calls `TimerStartPeriodicMs(t, 100)`; no `esp_timer_create` args,
`esp_intr_alloc`, or interrupt plumbing appear in app code.

`esp_timer` dispatches callbacks from a high-priority FreeRTOS task (not a
true ISR), so the handler has no ISR-safety restrictions. A hardware
timer-group true-ISR variant is a possible follow-up slice.

Known wart: the callback is marked `iram;` only because plain `@proc` fixups
aren't wired in the relocatable-object writer yet
(`bug-esp-emit-obj-proc-fixup-non-iram`); drop it when that lands.

## Build

```bash
. ~/esp/esp-idf/export.sh     # idf.py + toolchains on PATH
./build.sh                    # main.pas -> main.o -> libpxx_app.a -> idf.py build
./build.sh qemu               # boot under Espressif QEMU
```

**KNOWN BROKEN under qemu right now** (`bug-esp-idf-heap-linux-mmap-ecall`):
the builtin heap on the IDF profile still issues Linux `mmap` ecalls, so the
first string literal passed to `esp_rom_printf` panics
("Environment call from M-mode", MEPC in `HeapMmap`). The example builds and
links; it runs once that Track A ticket lands.

Expected qemu monitor output (once the heap ticket lands):

```
PXX timer: started
PXX timer: tick=1
...
PXX timer: tick=5
PXX timer: done ticks=5 status=0
```
