---
track: A
prio: 75
type: bug
---

# Every pxx ESP-IDF app panics at `app_main`: Linux syscalls emitted into the image

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

## Flags tried, none sufficient

Each rebuilt and re-booted individually; the `app_main` `ecall` survives all
three:

- `--platform=esp`
- `-dPXX_ESP_IDF`
- `--no-unhandled-handler` (the obvious candidate, since 134 is `rt_sigaction`)

So the handler install is not the only emitter, or the flag does not reach the
prologue emission.

## Relation to the resolved heap ticket

[[bug-esp-idf-heap-linux-mmap-ecall]] (resolved 2026-07-14, `98c1d40b`) is the
same *class* and fixed one instance — `HeapMmap`'s mmap. `HeapMmap` still
contains an `ecall` in this image, and four other emitters exist besides. That
ticket's acceptance said "hello-c3 rebuilt with the current compiler still
runs"; it does not, so either the fix regressed or it was narrower than the
acceptance implied. Worth reading before re-fixing, since its analysis of the
bare-vs-IDF profile split is still the right frame.

## Why it is Track A

`compiler/builtin` decides what the runtime emits, and the fatal call is in the
compiler-generated prologue of `app_main`. Nothing in `lib/rtl` or the examples
can suppress it — proven by `hello-c3`, which links neither.

## Gate

`examples/esp32/hello-c3` prints its `PXX hello ... / PXX sum 1..5 = 15`
sequence under `qemu-system-riscv32 -M esp32c3`, and
`examples/esp32/net-c3/build.sh qemu` reports the loopback smoke PASS. Both are
headless and already scripted; the QEMU binaries live under `~/.espressif` and
come onto PATH via `. ~/esp/esp-idf/export.sh`. Then re-check the image for
`ecall` — zero is the only right answer for an IDF-profile build.
