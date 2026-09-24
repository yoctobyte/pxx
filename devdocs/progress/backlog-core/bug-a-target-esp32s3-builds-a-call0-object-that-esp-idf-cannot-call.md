---
slug: bug-a-target-esp32s3-builds-a-call0-object-that-esp-idf-cannot-call
track: A
prio: 40
type: bug
blocked-by: []
summary: "A named xtensa chip (--target=esp32 / esp32s2 / esp32s3) on the IDF profile builds with the CALL0 ABI unless --xtensa-abi=windowed is spelled, and ESP-IDF on every xtensa chip is windowed: it enters app_main with callx8 and expects retw. So the chip name alone yields an object that links and cannot run -- the same silent-wrong-build class as the esp32c3 hosted-linux object fixed in 747054b6df. Every example and tools/esp_run.sh spell windowed by hand, which is why nothing booted wrong. The obvious fix (an xtensa SoC on a non-bare profile implies windowed unless --xtensa-abi is explicit) is NOT free: the test-xtensa row that builds lib_asyncnet6 as --target=esp32s3 --emit-obj passes only because it is call0 -- coroutines (CoSwitch) refuse on windowed -- so it certifies an object IDF cannot call."
---

# `--target=esp32s3` builds call0; IDF on the s3 is windowed

Found 2026-09-24 (frankS) while adding the s3 leg of the ESP C conformance run.

## Measured

- `--target=esp32s3 --emit-obj` vs `--target=xtensa --xtensa-abi=windowed
  --platform=esp --emit-obj` of `test/c_variadic_on_windowed_xtensa.c`:
  different objects (440715 vs 373009 bytes of code); the first is call0
  (`XtensaABI` defaults to `XTENSA_ABI_CALL0`, compiler.pas, and only
  `--xtensa-abi=windowed` changes it).
- All xtensa SoCs in the table (`SocIsXtensa`: esp32, esp32s2, esp32s3) run
  ESP-IDF windowed. Bare (`--esp-profile=bare`) is call0 by requirement, and
  the refusal of bare+windowed stays.

## Why it was not fixed with the finding

The decide ticket (`decide-esp-soc-axis-and-capability-table`) says a SoC
target implies the capability row, and the ABI is in that table's axes, so
the implication itself looks decided. Two things stand in the way:

1. `Makefile` test-xtensa: `--target=esp32s3 --emit-obj test/lib_asyncnet6.pas`
   ("THE ESP PARITY THIS WAS ACTUALLY FOR") goes red under windowed, because
   CoSwitch is call0-only and its negative control asserts windowed refuses.
   Making the chip imply windowed turns that parity row into a refusal. That is
   arguably the TRUE answer for IDF on the s3, but it changes a row someone
   wrote deliberately.
2. `c_crtl_s3.o` in test-emit-obj builds as call0 today for the same reason.

## Condition that would retire this

`--target=esp32s3 --emit-obj` producing an object whose `app_main` at .text+0
begins with `entry` (bytes `36 xx 00`), and a booted `tools/esp_run.sh
--chip esp32s3` of a program built with only the chip name.
