---
title: Targets
order: 60
---

# Targets

PXX can emit native and cross-target output from the same compiler invocation.

## Supported target names

| Target | Output | Typical run path |
| --- | --- | --- |
| `x86_64` | Native Linux ELF executable (the default). | Run directly on x86-64 Linux. |
| `i386` | 32-bit Linux ELF executable. | Run directly on hosts with i386 support, or via `qemu-i386`. |
| `aarch64` | 64-bit ARM Linux ELF executable. | Run via `qemu-aarch64` on non-ARM hosts. |
| `arm32` | 32-bit ARM Linux ELF executable. | Run via `qemu-arm` on non-ARM hosts. |
| `riscv32` | 32-bit RISC-V Linux ELF, or an ESP32-C3 object or bare-metal image. | Linux binaries run via `qemu-riscv32`; for ESP see [ESP32](./esp32.md). |
| `xtensa` | ESP32-S2/S3 object or bare-metal image. | See [ESP32](./esp32.md). |
| `wasm32` | WebAssembly module. | Run with `wasmtime`. |

`pxx --list-targets` prints this list for your build. From pin v425 it
describes wasm32 as `via wasmtime` for Pascal, C and Nil Python; v424 wrongly
said "registered only — no codegen yet". The table below shows what wasm32
actually does.

ESP chip names are accepted as targets too. They imply the CPU and
`--platform=esp`: `esp32`, `esp32s2` and `esp32s3` are xtensa; `esp32c2`,
`esp32c3`, `esp32c6`, `esp32h2` and `esp32p4` are riscv32. Pin v445 compiles
an ESP-IDF object for every one of these names (re-checked 2026-09-27). The bare-metal profile supports
only `esp32s3` and `esp32c3`, and says so for the others. It runs under QEMU
only; on a real board use the ESP-IDF profile (see
[known issues](../reference/known-issues.md)). The ESP32-S3 and the
ESP32-C3 have been run on physical boards (with the ESP-IDF profile); the
rest have only been compiled.

Use `--target=ARCH` before the source file:

```sh
./pxx --target=aarch64 hello.pas hello.a64
```

For Linux cross-target executables, `tools/run_target.sh` chooses the right QEMU
user-mode runner when the host cannot execute the file directly.

```sh
tools/run_target.sh aarch64 ./hello.a64
```

For ESP32 targets, start with the board-specific examples under
`examples/esp32/`; the peripheral units are in
[ESP32 peripherals](../library/esp.md).

## FreeBSD

`--os=freebsd` (EXPERIMENTAL, like every kernel but Linux) writes a native
FreeBSD/amd64 executable from Pascal, C or Nil Python:

```sh
./pxx --os=freebsd hello.pas hello.fbsd
```

The program needs no libc, like a Linux build. The runtime is unchanged:
every system call goes to a small Linux-to-FreeBSD translator compiled into
the program. It maps the call numbers, flags, structs, signals and errno
values. Measured on FreeBSD 15.1; FreeBSD 14 or newer is needed (timerfd).

What works, each checked against the Linux build of the same test (`make
test-freebsd`, which needs the VM from `tools/vm/freebsd.sh`): files and
directories, environment and arguments, processes and `wait`, signals
(including turning a crash into an exception), `select`/`poll`, the
async scheduler (epoll is emulated on kqueue), sockets (IPv4, IPv6, Unix),
terminals and ptys, and `--threadsafe` threads.

Not supported: other CPUs, `--shared`, `--emit-obj` and `--rtl-libc` (all
refused at compile time), threads through glibc's `pthread_create`, and
Linux-only interfaces. Anything the translator does not know returns `ENOSYS`.
The details, how to test in the VM, and the plan for OpenBSD and NetBSD are in
[FreeBSD and the BSDs](./freebsd.md).

## Windows

`--os=windows` (EXPERIMENTAL, phase 1) writes a Windows x64 console `.exe`
that imports only `kernel32.dll`. It uses the same translator design as the
BSD targets, with kernel32 underneath. Phase 1 covers the console, the heap,
exceptions, time and arguments. Files, threads and sockets come next. See
[Windows](./windows.md).

## OpenWrt

OpenWrt is Linux, so a normal pxx Linux build for the router's CPU runs on it
unchanged. The program needs nothing from OpenWrt's musl libc or BusyBox.

- **x86-64, aarch64 and ARMv7 (`arm32`):** measured on OpenWrt 25.12.6 in
  QEMU (2026-11-12), with Pascal, C and Nil Python programs, sockets, signals
  and `--threadsafe` threads. The output was identical to the same program
  on the host. pxx's arm32 code needs ARMv7-A with VFP, so ARMv5 and ARMv6
  boards (Kirkwood, Raspberry Pi 1) are not supported.
- **MIPS:** not supported. pxx has no MIPS backend, and most older and cheaper
  routers (ath79, MT7621) are MIPS.

Copy the binary to the router and run it:

```sh
./pxx --target=aarch64 hello.pas hello
ssh root@192.168.1.1 'cat > /tmp/hello && chmod +x /tmp/hello && /tmp/hello' < hello
```

OpenWrt has no SFTP server by default, so a plain `scp` fails with
"Connection closed". Use `scp -O` (the older protocol), or pipe the file
through `ssh` as above.

Two fixes from 2026-11-12 matter here, so use a compiler from that date or
later:

- Programs that allocate memory failed on routers with 256 MB of RAM or less.
  The heap asked for one 256 MiB block, and Linux refused it. The heap now
  retries with smaller blocks.
- On real 32-bit ARM hardware, `--threadsafe` threads never started:
  creating a thread failed with `EAGAIN`. The kernel places memory above
  `0x80000000` there, and the runtime mistook those addresses for errors.
  Emulators place memory lower, so the tests run under QEMU's user-mode
  emulation had not shown it.

## What each target supports

Measured with **pin v445** (compiler sha256 `caf21ac399f1…`) on 2026-09-27;
every cell is the same as with v425. Programs other than x86-64 ones were run
under QEMU user mode, and wasm32 under wasmtime; none of the Linux cross
targets was run on real hardware for this table. The probes: a class with an
exception caught and a line written; `writeln(SizeOf(Real))`;
`test/lib_classes_tthread.pas` and `test/c_pthread_detach.c`; a `threadvar`
set and read; `--emit-obj` on `test/c_obj_data_export.c`; `--shared` on
`test/test_library_exports.pas`; a Nil Python `sum` of a list; and C's
`sqrt(2.0)`.

| | x86-64 | i386 | aarch64 | arm32 | riscv32 Linux | wasm32 |
| --- | --- | --- | --- | --- | --- | --- |
| Pascal classes, exceptions, console I/O | yes | yes | yes | yes | yes | yes |
| `SizeOf(Real)` | 8 | 8 | 8 | 8 | 4 | 8 |
| Threads (`TThread`, C `pthread_create`) with `--threadsafe` | yes | yes | yes | yes | refused | refused |
| Pascal `threadvar` | yes | yes (from v446) | yes | yes | refused | refused |
| `--emit-obj` (relocatable object) | yes | yes | yes | yes | yes | refused |
| `--shared` (shared library) | yes | refused | refused | refused | refused | refused |
| Nil Python | yes | yes | yes | yes | refused | yes |
| C with `#include <math.h>` | yes | yes | yes | yes | yes | yes |

Compared with v424, one cell changed: wasm32 C with `math.h` was refused
there. **Pascal `threadvar` on i386 is refused with v445 and works from
v446** (`7dc976a8cc`, which also gives each i386 thread its own C `__thread`
copies). On 2026-09-28, the two thread rows were measured again with pin v446
(`ae3466a018d8`) and with the compiler at `e072d579b0`, under QEMU: each
thread kept its own `threadvar` and `__thread` values on x86-64, i386,
aarch64 and arm32. See [Threads & parallelism](../library/concurrency.md#targets).

Every **refused** cell is a compile-time error that names the reason; none
produces a program that runs wrongly. Most messages say in plain words what is
unsupported, for example `--threadsafe is available for x86-64, i386, aarch64
and arm32 only; it is refused for riscv32.` and, for every target but x86-64,
`--shared: shared-library output is x86-64 only`. `xtensa` also has an object
writer; it is the ESP-IDF route.

## Pages

- [FreeBSD and the BSDs](./freebsd.md)
- [Cross-compilation](./cross-compilation.md)
- [Cross languages](./cross-languages.md)
- [C Frontend](./c-frontend.md)
- [Nil Python](./nil-python.md)
- [Other frontends](./other-frontends.md)

## Next

- [Command-line reference](../reference/cli.md)
