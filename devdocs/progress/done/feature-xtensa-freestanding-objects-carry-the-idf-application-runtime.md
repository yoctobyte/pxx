---
slug: feature-xtensa-freestanding-objects-carry-the-idf-application-runtime
track: C
prio: 30
type: feature
status: done
created: 2026-11-16
found-by: pxx (Gibux seat) at f2629553ba, gibux docs/tickets/0004
tags: [esp, xtensa, size, freestanding]
blocked-by: []
summary: "DONE 2026-11-17: a freestanding ESP object (xtensa and riscv32) now takes the bare runtime with the chip's own ABI (windowed on a named xtensa chip), has no undefined symbol, exports app_main WEAK, and carries its C initialisers as .data with R_XTENSA_32/R_RISCV_32 relocations. Before, it carried an ESP-IDF application runtime, about 7 KB each (app_main, PXXIdfStdWrite, PXXSysWrite, __pxx_atexit_run, PXXNilRef 1.8 KB); x86-64 freestanding objects carry 1.4 KB. Gibux lib/string.c: 12 KB pxx vs 0.6 KB xtensa gcc -Os. Not blocking: Gibux has no ESP32 port."
---

## Done 2026-11-17

The Gibux seat started an ESP32-S3 port (no FreeRTOS, its own entry and
linker script), and measuring this ticket turned up a worse problem than size.
Before the change, an xtensa `--freestanding --emit-obj` object:

- carried the IDF platform backend, with UNDEFINED references to lwip_*,
  fopen, esp_netif_init, heap_caps_* and others, so it would not link without
  ESP-IDF;
- put `int gv = 5;` in .bss and set it from the app_main stub. The kernel never
  runs that stub, so the value read 0. Under `--esp-profile=bare --emit-obj`
  the initialiser was dropped entirely, with no store anywhere.

### Changes

- **`EspFreestandingObj`** (compiler.pas). `--freestanding --emit-obj` on
  riscv32 or xtensa sets EspBareBoot, so the bare runtime is used and there
  are no IDF imports. It does not take on the bare image's limits: the
  windowed refusal and the S3/C3-only memory-map refusal are skipped, and a
  named xtensa chip stays windowed (gcc's default, and what the kernel's own
  window handlers serve).
- **Initialisers as .data**. CPlaceGlobalInData and CTryBakeGlobalInit (both
  x86-64-only until now) run for these objects. When the object has no
  `main`, the initialisers are walked after parsing; one that would need code
  at run time is refused by name. The two ESP writers place a baked global's
  symbol in .data or .rodata (`ObjEspDataSymLoc`) and emit one type-1
  relocation per baked address (`ObjEspCdrRel`). `ObjRoDropDeadStrings` now
  sees those references.
- **app_main is WEAK** in a freestanding object, so two objects never
  collide and the kernel's own app_main wins.
- **Pointer casts in initialisers** (rump-pxx g19, every target):
  `(volatile unsigned *)0x60000000`, `(const void *)&x` and `((void *)0)`
  bake through the cast, and so does `arr + k` on a global array.
- **A crash found on the way**: `Strs[InternStr(..)]` in CBakeAddrValue read
  the old array after InternStr grew it. The first string literal that grew
  the table segfaulted the compiler.

### Size

`int get(void){...}` with two globals is now 101 bytes of code. Before, it was
about 4.7 KB plus the import table.

### Tests

- `test/c_freestanding_static_data.c`. On x86-64, `--freestanding --emit-obj`
  is linked by gcc and run (the frozen compiler refuses `uart`). On xtensa,
  `tools/check_xtensa_freestanding_obj.py` checks the object (no undefined
  symbol, app_main weak, entry/retw), links it with GNU ld and reads every
  word back.
- riscv32 (esp32c3) was checked by hand the same way and has no row.
