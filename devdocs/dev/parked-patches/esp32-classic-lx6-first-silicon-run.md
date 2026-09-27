# PARKED — the first run of pxx on a CLASSIC ESP32 (Xtensa LX6)

**Parked 2026-09-27 by `frankz-e5` on a priority change from the owner (relayed
by frankuser), NOT because it hit a wall.** Nothing here is blocked. The board
is still plugged in, still mine, and the remaining work is one command.

**There is no patch beside this note.** Everything got landed, because it is all
additive and none of it changes an existing path: `examples/esp32/hello-esp32/`
(new) and a fourth chip arm in `tools/esp_flash.sh`. A `.patch` would have been
a worse artefact than a committed directory that says in its own README what has
not been run.

## The board

| | |
| --- | --- |
| part | ESP32-D0WD-V3 rev v3.1, dual-core Xtensa **LX6** at 240 MHz |
| MAC | `e0:8c:fe:57:bb:b8` |
| bridge | CP2102 (so it is a `/dev/ttyUSB*`, not a native USB-JTAG `ttyACM*`) |
| port | `/dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0` |
| access | `sg dialout -c "<command>"` — `neo` IS in `dialout` in `/etc/group`, but this login predates the change, so the process's group set does not have it. No sudo and no chmod is needed or wanted. |

**Two other boards are plugged in and are NOT this seat's:** the C3 is
`frankb-12`'s and the S3 is `frankd-a3`'s. **An esptool call resets a board**, so
touching the wrong port interrupts another seat's run. Address the port by its
`by-id` name, never by `ttyUSB0`, which is a number the kernel hands out in
plug order.

## What was done, and on what

Tree `479b8e495e`; `compiler/pascal26` sha256 **`4ebfa2d047a2`**, built here with
`converged after 2 round(s)`. That sha **is the release pin v441's binary**
(AGENTS.md records v441 as `5c1696ca79` / `4ebfa2d047a2`), i.e. `compiler/**` has
not moved since the pin, so every number below is the released compiler's.

1. **`examples/esp32/hello-esp32/`** — the IDF hello for this part. Its
   `main/main.pas` is `hello-s3/main/main.pas` with the printed words changed and
   **nothing else**: same GPIO pin, same bounds, same externals. Deliberate — the
   question is whether xtensa codegen runs on LX6 as on LX7, and holding the
   program fixed is what makes a difference attributable to the chip.
2. **`tools/esp_flash.sh` grew an `esp32` arm** — `--chip esp32`, a `*-esp32`
   suffix rule for `--project`, `PXXFLAGS="--target=esp32"`, and the usage and
   unknown-chip strings. Its `--help` range moved from `2,45p` to `2,49p`,
   because the header grew and the help had started truncating mid-sentence.
3. **The pxx compile is proven, for the chip and for a control:**

   | | code | data | bss | procs |
   | --- | ---: | ---: | ---: | ---: |
   | `--target=esp32` | 24,579 B | 4,672 B | 1,336 B | 207 |
   | `--target=esp32s3` (same source) | 24,579 B | 4,656 B | 1,336 B | 207 |

   Identical code size; 16 bytes more data on the classic part.

4. **The ESP-IDF build runs and links.** `./build.sh` under ESP-IDF **v6.0.1**:
   1007 ninja steps, `pxx_hello_esp32.bin` **166,752 B**, and the project's own
   assertion `app_main present in image map` (at `0x400d9854`). So the whole
   toolchain path — pxx object, `xtensa-esp32-elf-ar`, IDF's esp32 linker
   scripts, the `-u app_main` keep — is proven for this part. The ONE unrun step
   is writing it to the board.

## What was NOT done, stated so nobody quotes this as a result

**No pxx code has ever executed on an LX6.** Not under qemu from this seat
either. The chip table in `docs/targets/esp32.md` still says `esp32` is
"accepted and compile[s] to an ESP-IDF object, but nothing has been run on
[it]", and that sentence is still true. **The compile numbers above are not a
run**, and a project directory existing is not a run.

## To finish it — the whole remaining job

    sg dialout -c "tools/esp_flash.sh --chip esp32 \
      --port /dev/serial/by-id/usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0 \
      --no-verify --seconds 12 examples/esp32/hello-esp32/main/main.pas"

`--no-verify` because the program's externals (`esp_rom_printf`, `gpio_*`,
`vTaskDelay`) do not exist on x86-64, so there is no native oracle to diff
against; the script detects that and continues anyway, but saying it is clearer
than letting it be inferred. Expect five `PXX hello from Pascal ESP32: i=N`
lines and `PXX ESP32 sum 1..5 = 15`.

**If it faults**, the panic dump gives a PC: disassemble it in
`build/pxx_hello_esp32.elf` with `xtensa-esp32-elf-objdump -d` and answer the
one question that matters — **an LX7-only instruction, or configuration?** The
axes that differ are in the project README. One predicate to re-measure if an
atomic faults: `SocHasAtomicISA` (`compiler/defs.inc:9107`) claims S32C1I for
this part, from IDF's `esp32` core-isa.h having `XCHAL_HAVE_S32C1I = 1`.

**Then record it in `docs/targets/esp32.md`'s chip table** with the compiler
sha, the tree and the board — that table is the deliverable, not this note.

## One thing worth a ticket that is not about the ESP32 at all

`pascal26` refuses an output path whose **directory does not exist** with
*"a write to the output file stored fewer bytes than asked"*, followed by a
four-item checklist — free bytes, free inodes, `ulimit -f`, a concurrent writer.
**The real cause is not on the list.** Measured here 2026-09-27: the same source
failed for `--target=esp32` AND for `--target=esp32s3`, which is what stopped it
being read as an LX6 defect; `df -h` said 90 G free, `df -i` said 1 %, `ulimit
-f` unlimited, no second writer. The directory (a session scratchpad under
`/tmp`) had been reaped. A checklist that is correct about four causes and
silent about the fifth sends the reader to measure four healthy things — the
house failure of an instrument that lies by being correct about something else.
Cheap fix: `stat` the parent directory and say so.
