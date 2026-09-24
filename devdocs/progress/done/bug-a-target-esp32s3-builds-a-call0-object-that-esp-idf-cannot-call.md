---
slug: bug-a-target-esp32s3-builds-a-call0-object-that-esp-idf-cannot-call
track: A
prio: 40
type: bug
blocked-by: []
summary: "FIXED 2026-09-24. A NAMED xtensa chip (--target=esp32 / esp32s2 / esp32s3) on the IDF platform now defaults to the WINDOWED ABI unless --xtensa-abi= is spelled; ESP-IDF enters app_main with CALLX8 and expects RETW, so the old Call0 default built an object that linked and could not run. Generic --target=xtensa keeps Call0 (the qemu linux-user spelling), and --esp-profile=bare keeps Call0 by requirement. The fork that held it -- coroutines were Call0-only, so the s3 asyncnet6 parity row certified an uncallable object -- was closed by building the windowed CoSwitch (feature-a-a-windowed-abi-coswitch-for-xtensa), not by refusing. Guard: test-xtensa's relation rows (chip-name object == spelled-windowed, != spelled-call0)."
status: done
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


## Resolution (2026-09-24, frankH)

Both halves were done in one change, since neither is correct alone.

- **The default:** `compiler.pas`, after DeriveTargetPlatform. The rule is
  `SocExplicit and SocIsXtensa and not XtensaAbiExplicit and not EspBareBoot
  and TargetPlatform = PLATFORM_ESP` => windowed. `XtensaAbiExplicit` is new,
  so `--xtensa-abi=call0` still means call0.
- **The coroutines:** the windowed CoSwitch, recorded in
  feature-a-a-windowed-abi-coswitch-for-xtensa.

**The retire condition, both halves measured:**
- `--target=esp32s3 --emit-obj` gives an app_main that opens with
  `entry a1, 64`.
- A program built with ONLY `--target=esp32s3` booted and matched its x86-64
  oracle:
  - under S3 QEMU;
  - on an ESP32-S3 BOARD, via tools/esp_flash.sh, whose s3 case now spells
    just the chip name (so does tools/esp_run.sh);
  - the program was test_scheduler_yields_deep_in_a_call_chain, 8 of 8 lines.
- esp32 and esp32s2 chip-name objects are byte-identical to spelled-windowed.
- `--target=esp32s3 --esp-profile=bare` still builds.

**What the s3 asyncnet6 row now asserts:** the same command line, and it now
builds a WINDOWED object. It still passes, now for the right reason.

**Not changed:** esp_flash.sh's esp32s2 case still spells the generic
xtensa. `--target=esp32s2` would also move the SoC from the implied s3 to a
real s2, and no s2 was available to verify that.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
