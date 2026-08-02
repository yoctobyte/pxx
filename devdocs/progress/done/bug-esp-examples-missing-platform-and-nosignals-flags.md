---
track: B
prio: 60
type: bug
---

# ESP examples panic at `app_main`: their build scripts omit two required flags

**RESOLVED 2026-08-02 — and re-laned A -> B: this is not a compiler bug.**

- **Type:** bug (runtime/codegen for the ESP profile) — **Track A**
  (`compiler/builtin`, syscall emission). Filed by the Track B agent, who has
  no business fixing `compiler/**`.
- **Found:** 2026-08-02, establishing a baseline before starting
  [[feature-dns-esp-backend]].

## Symptom

Both committed ESP examples boot the SoC correctly and then die the instant
control reaches Pascal:

```
I (218) main_task: Calling app_main()
Guru Meditation Error: Core  0 panic'ed (Environment call from M-mode).
Exception was unhandled.
Rebooting...
```

and boot-loop — ~120-150 reboots in a 25-second QEMU run.

An `ecall` is a RISC-V syscall instruction. There is no Linux kernel under
FreeRTOS to service it, so the first one taken is fatal.

## Measured

- **`examples/esp32/net-c3`** — `./build.sh qemu` builds cleanly (`app_main
  present in image map`) and reports `esp32c3 lwIP loopback socket smoke: FAIL`.
- **`examples/esp32/hello-c3`** — same panic. This one matters: its `build.sh`
  passes **no `-Fu` at all**, so it links none of `lib/rtl` and no PAL backend.
  The fault is therefore *not* in the PAL.
- **Pre-existing.** Rebuilt against `lib/rtl` from before this session's first
  commit (`77060e5f7`): identical panic, identical loop. Not caused by the
  2026-08-02 Track B work.

`objdump` on the linked ELF places the `ecall`s:

| address | enclosing symbol |
| --- | --- |
| `4200b190` | **`app_main`** — `li a7,134` = `rt_sigaction` |
| `4201a95c` | `HeapMmap` |
| `4202af68` | `PXXDivZero` |
| `420318c4` | `PXXWriteFloatSci` |

Syscall numbers loaded anywhere in the image: **64** (write), **94**
(exit_group), **129** (kill), **134** (rt_sigaction), **172** (getpid).

The one in `app_main` is the fatal one — it is in the prologue, before any user
statement runs, which is why even a program that only calls
`esp_rom_printf`/`vTaskDelay` dies.

## Flags tried individually — the misleading step

Each rebuilt and re-booted on its own; the panic survived all three, which is
what sent this to the wrong lane. See the Resolution above for why.

## Relation to the resolved heap ticket

[[bug-esp-idf-heap-linux-mmap-ecall]] (resolved 2026-07-14, `98c1d40b`) is the
same *class* and fixed one instance — `HeapMmap`'s mmap. `HeapMmap` still
contains an `ecall` in this image, and four other emitters exist besides. That
ticket's acceptance said "hello-c3 rebuilt with the current compiler still
runs"; it does not, so either the fix regressed or it was narrower than the
acceptance implied. Worth reading before re-fixing, since its analysis of the
bare-vs-IDF profile split is still the right frame.

## Resolution: two missing flags, and each is silent on its own

The compiler already has both switches. The example `build.sh` scripts simply
did not pass them:

| flag | what it suppresses |
| --- | --- |
| `--platform=esp` | auto-defines `PXX_ESP_IDF`, backing `PXXAlloc` with the IDF heap (`calloc`/`free` externals). Without it the heap takes the hosted-linux branch and `mmap` is an `ecall`. |
| `--no-signals` | omits the SIGINT/SIGTERM runtime, whose install is the `rt_sigaction` `ecall` in `app_main`'s prologue. |

**Neither alone is enough**, which is what made this look like a compiler defect:
each leaves a different fatal `ecall` behind, so testing them one at a time
"disproves" both. Together:

```
--target=riscv32 --platform=esp --no-signals
```

- `hello-c3`: boots ONCE, no panic, prints `PXX hello from Pascal: i=1..5` and
  `PXX sum 1..5 = 15`.
- `net-c3`: boots once and prints `PXX-net-smoke status=0` — the lwIP loopback
  socket smoke passes.

### How I got the lane wrong

I filed this Track A after testing `--platform=esp`, `-dPXX_ESP_IDF` and
`--no-unhandled-handler` **individually** and seeing the panic survive each.
Two errors:

1. `--no-unhandled-handler` is not the signals flag. It gates the
   *unhandled-exception message printer*; `--no-signals` gates the signal
   runtime. Measured afterwards: `--no-unhandled-handler` produces a
   **byte-identical** object on `--target=riscv32` — it does nothing there.
2. Testing flags one at a time cannot find a fix that needs two. Each single
   flag leaves a different `ecall`, so every individual test looks like a failure.

`-dPXX_ESP_IDF` by hand was also wrong: that define is *derived* from
`--platform=esp` in `lexer.inc`, and setting it directly does not select the
rest of the platform.

## Fixed in

`examples/esp32/{hello-c3,net-c3,timer-c3}/build.sh` now pass both flags, with a
comment naming the failure mode — `timer-c3` had `--platform=esp` but not
`--no-signals`, i.e. exactly half the recipe.

Still to check: `examples/esp32/hello-s3` (xtensa) passes neither. The signal
runtime is gated on `TARGET_RISCV32`, so xtensa may not need `--no-signals`, but
it does want `--platform=esp` for the heap. Left unchanged pending a real
`qemu-system-xtensa -M esp32s3` boot rather than guessed at.

## Gate

`examples/esp32/hello-c3` prints its `PXX hello ... / PXX sum 1..5 = 15`
sequence under `qemu-system-riscv32 -M esp32c3`, and
`examples/esp32/net-c3/build.sh qemu` reports the loopback smoke PASS. Both are
headless and already scripted; the QEMU binaries live under `~/.espressif` and
come onto PATH via `. ~/esp/esp-idf/export.sh`. Then re-check the image for
`ecall` — zero is the only right answer for an IDF-profile build.
