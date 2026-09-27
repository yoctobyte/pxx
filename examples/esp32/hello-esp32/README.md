# hello-esp32 — PXX on the CLASSIC ESP32 (Xtensa LX6)

The ESP-IDF integration hello for the **original** ESP32, the part with the
Xtensa **LX6** core. Everything else under `examples/esp32/` targets an LX7
(S2/S3) or a RISC-V part (C3).

    tools/esp_flash.sh --chip esp32 --port /dev/serial/by-id/<your-board> main/main.pas
    # or, to build exactly what this project is:
    ./build.sh

## What has and has not been run — read this before quoting it

Measured 2026-09-27, tree `479b8e495e`, compiler `compiler/pascal26` sha256
`4ebfa2d047a2` (which is the release pin **v441**'s binary — `compiler/**` has
not moved since the pin, so these are the released compiler's numbers).

| step | state |
| --- | --- |
| `pxx --target=esp32` compiles `main/main.pas` to a relocatable object | **done** — `code=24579B data=4672B bss=1336B procs=207` |
| the same source for `--target=esp32s3` (control) | **done** — `code=24579B data=4656B bss=1336B`, i.e. identical code size, 16 B more data |
| the ESP-IDF build (`./build.sh`: `idf.py set-target esp32 && idf.py build`) | **done** — ESP-IDF **v6.0.1**, 1007 ninja steps, image `pxx_hello_esp32.bin` **166,752 B**, and `app_main present in image map` at `0x400d9854` |
| **flashed to a physical ESP32** | **NOT DONE.** Nothing in this directory is evidence that pxx code has ever executed on an LX6. |

The chip table in `docs/targets/esp32.md` is the place that records a board
result, and it has not been changed by this project's existence. If you run
this on silicon, update that table and this one.

## Why this program is a copy of hello-s3's

`main/main.pas` is `examples/esp32/hello-s3/main/main.pas` with the printed
words changed and nothing else — same GPIO pin, same loop bounds, same
externals. The open question this project exists for is whether pxx's xtensa
codegen runs on LX6 as it does on LX7, and **holding the program axis fixed is
what makes a difference attributable to the chip.** Change the program and the
comparison stops being one.

## Why `--target=esp32` and not `--target=xtensa`

The generic `--target=xtensa` spelling answers the **S3's** memory map
(`SocIramBase` gives `$40378000` for every xtensa chip) and its instruction
set. The chip name selects the LX6 and, on the IDF platform, also selects the
**windowed** ABI, which is what ESP-IDF's startup task calls `app_main` with
(CALLX8, expecting RETW). A Call0 object links and cannot run.

`--esp-profile=bare` is **refused by name** for this chip and that refusal is
correct: the bare image hardcodes the C3/S3 load address and a UART0 base of
`$60000000`, where the classic ESP32's is `$3FF40000`. Use the IDF profile,
which is what this project is.

## The things to suspect first if it faults on a board

Not a list of known bugs — nothing here has been measured on silicon. These are
the axes that differ between LX6 and LX7 and are therefore where to look:

- **An LX7-only instruction.** Get the fault PC from the panic dump and
  disassemble that address in `build/pxx_hello_esp32.elf` with
  `xtensa-esp32-elf-objdump -d`. `SocHasAtomicISA` in `compiler/defs.inc` claims
  S32C1I for this part (IDF's `esp32` core-isa.h has
  `XCHAL_HAVE_S32C1I = 1`), so an atomic is *expected* to be legal here — if a
  fault lands on one, that predicate is the thing to re-measure.
- **Config rather than ISA.** A `LoadStoreError` or an alignment fault is more
  likely a memory-map or cache-config difference than a bad opcode.
- **Dual core.** `SocCoreCount` answers 2 for this part, as for the S3.
