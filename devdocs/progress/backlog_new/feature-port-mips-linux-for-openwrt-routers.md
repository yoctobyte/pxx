---
track: A
prio: 40
type: feature
status: backlog
owner: ""
created: 2026-11-12
found-by: owner question + pxx2 session (OpenWrt smoke test)
blocked-by: []
tags: [portability, mips, openwrt, linux, backend]
summary: "MIPS Linux backend, for the OpenWrt routers people actually own (ath79 MIPS 24Kc big-endian, ramips MT7621 MIPS 1004Kc little-endian, lantiq). Everything else OpenWrt runs already works: pxx x86-64 and aarch64 binaries run unchanged on OpenWrt 25.12.6 (measured 2026-11-12 in QEMU), ARMv7 expected. MIPS is a new backend in the xtensa class of work: codegen, assembler, ELF writer, and the MIPS o32 syscall ABI (own numbers, errno in a3, own errno values)."
---

# MIPS Linux backend (OpenWrt routers)

## Why

The owner asked what OpenWrt runs. OpenWrt is Linux (kernel 6.12 in 25.12.6)
with musl and BusyBox; pxx binaries need no libc, so what matters is the CPU.

| OpenWrt hardware | CPU | pxx |
| --- | --- | --- |
| x86 boxes, VMs | x86-64 / i386 | works (x86-64 measured) |
| MediaTek Filogic, Qualcomm IPQ807x/60xx, Raspberry Pi 3/4/5 | aarch64 | works (measured) |
| IPQ40xx, mvebu, Raspberry Pi 2 | ARMv7 hard-float | works (measured, after the thread fix below) |
| Kirkwood (ARMv5), Raspberry Pi 1 (ARMv6) | older ARM | no: arm32 codegen is ARMv7-A with VFP |
| ath79, ramips MT7621, lantiq -- most routers in use | MIPS | **no backend** |

## What it takes

- Codegen + assembler for MIPS32r2 (24Kc / 1004Kc), both endiannesses
  (ath79 is big-endian, MT7621 little-endian). No FPU on most of these
  chips: the kernel emulates FP, so soft-float (`compiler/builtin/softfloat.pas`,
  already used on ESP) is the realistic default.
- ELF writer: EM_MIPS, o32 flags, endianness.
- Syscall ABI: o32 numbers start at 4000, the error flag comes back in a3,
  and MIPS has its own errno and signal numbers -- a per-arch constants table
  in the RTL, not a translator (it is still Linux).
- Test: OpenWrt `malta` images boot in qemu-system-mips(el); qemu-user
  `qemu-mips`/`qemu-mipsel` for the per-test lane.

## Measured 2026-11-12 (pxx2-bsd)

OpenWrt 25.12.6 in QEMU, 236 MB / 232 MB RAM, no swap. Host vs router, same
binary, 12 tests (Pascal, C, NilPy, sockets, signals, select, fallocate,
heap, three --threadsafe thread tests):

- x86-64: all identical after one fix (below), except stdout/stderr ordering
  over ssh.
- aarch64 (`armsr/armv8`): all identical; lib_sockets differs only because
  qemu-user on the host returns a different errno for socket(-1,-1,-1) --
  the real kernel on the router answers as Linux does.
- **Fixed on the way:** the heap's first 256 MiB arena map was refused on a
  256 MB router (Linux overcommit heuristic: one mapping larger than RAM +
  swap fails), so every program that allocated died with "out of memory".
  The heap now retries at half size down to 64 KiB;
  test/test_heap_small_address_space.pas (test-core, under ulimit -v).

VM images (not in git): `/data/vm/openwrt` on plexus.

## Log

- 2026-11-12 — filed from the OpenWrt smoke test (pxx2 session). Not claimed.
- 2026-11-12 — ARMv7 measured (`armsr/armv7`, initramfs kernel booted with
  `qemu-system-arm -M virt -kernel`, no UEFI firmware needed). Single-threaded
  tests were identical at once; every `--threadsafe` thread failed with
  EAGAIN. Cause: arm32 sign-extends a raw syscall return, so the real
  kernel's stack mmap at 0xac8c1000 arrived negative, and palthread tested
  the sign (`StackBase < 0`, `blk > 0`; scheduler.pas the same for coroutine
  stacks, where it silently fell back to an unguarded heap stack). qemu-arm
  maps low, which is why the emulated lane never saw it. Fixed with an
  errno-range test (MmapOk, as builtinheap's HeapMmapFailed);
  test/c_thread_high_address_stack.c in test-threads fails before the fix
  under qemu-arm and on the router.
