#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Run a PXX-emitted binary for a given CPU target, under QEMU user-mode
# emulation when the host cannot execute it natively.
#
#   tools/run_target.sh <arch> <binary> [args...]
#
# arch: x86_64 | i386 | aarch64 | arm32 | riscv32 | riscv64 | xtensa
#
# Exit code is the program's exit code (QEMU passes it through), so the
# existing `test "$(...)" = ...` Makefile assertions work unchanged.
# PXX binaries are static and syscall-only, so no -L sysroot is needed;
# if a dynamically linked test ever crosses an arch boundary it must add
# QEMU_LD_PREFIX for the target's interpreter.
set -eu

if [ $# -lt 2 ]; then
  echo "usage: $0 <arch> <binary> [args...]" >&2
  exit 2
fi

arch="$1"; shift
bin="$1"; shift

# Dynamically linked PXX binaries (external C calls) need the guest ld.so + libc.
# If a sysroot was provisioned (tools/install_cross_sysroot.sh) and the caller
# did not already set QEMU_LD_PREFIX, point QEMU at it. Harmless for the common
# static/syscall-only binaries.
xroot="${PXX_CROSS_SYSROOT:-$HOME/.cache/pxx-cross}"
if [ -z "${QEMU_LD_PREFIX:-}" ] && [ -d "$xroot/$arch" ]; then
  QEMU_LD_PREFIX="$xroot/$arch"
  export QEMU_LD_PREFIX
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 not found; run tools/install_qemu.sh" >&2
    exit 2
  fi
}

case "$arch" in
  x86_64)
    exec "$bin" "$@"
    ;;
  i386)
    # x86-64 kernels usually exec i386 ELF natively (ia32 emulation);
    # prefer that, fall back to qemu-i386.
    #
    # stderr is NOT redirected. It used to go to /dev/null, so every i386 run
    # silently dropped the program's own diagnostics — and callers that compare
    # combined stdout+stderr byte-for-byte (tools/run_c_conformance.sh) were
    # comparing output the program never got to produce. Capturing it to a file
    # and replaying it afterwards is not equivalent either: that reorders it
    # against buffered stdout, and the interleaving is part of what is compared.
    # The cost is one "cannot execute binary file" line from the SHELL on a host
    # that cannot exec i386 ELF, just before the qemu fallback — loud and
    # diagnosable, unlike silently losing every program's stderr.
    if "$bin" "$@"; then exit 0; else rc=$?; fi
    # ENOEXEC surfaces as 126 from sh; anything else is the program's own exit
    # code — pass it through.
    if [ "$rc" != 126 ]; then exit "$rc"; fi
    need qemu-i386
    exec qemu-i386 "$bin" "$@"
    ;;
  aarch64)
    need qemu-aarch64
    exec qemu-aarch64 "$bin" "$@"
    ;;
  arm32)
    need qemu-arm
    exec qemu-arm "$bin" "$@"
    ;;
  riscv32)
    need qemu-riscv32
    exec qemu-riscv32 "$bin" "$@"
    ;;
  riscv64)
    need qemu-riscv64
    exec qemu-riscv64 "$bin" "$@"
    ;;
  xtensa)
    # Hosted xtensa under qemu-xtensa user mode. Newest arm, and the only one
    # whose target was unrunnable until 2026-08-29: xtensa had no IR_SYSCALL
    # lowering, no exit syscall, and no HeapMmap arm, so every binary either
    # spun in EmitExit's self-loop or faulted at $FFFFFFFF on its first
    # allocation. feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle
    #
    # TWO THINGS THE CALLER MUST GET RIGHT, and neither is visible here because
    # both are COMPILE-time:
    #
    #   --platform=posix, or the ESP PAL is selected and syscalls lower to
    #   PAL_ERR_UNSUPPORTED (-38) instead of trapping to the kernel.
    #
    #   --xtensa-soft-mulhigh, or ANY numeric output SIGILLs. No qemu-xtensa
    #   core implements MUL32HIGH -- measured, all 8 cores -- and integer
    #   formatting strength-reduces div-by-10 into a 64-bit multiply. Under
    #   that flag the emulator is NOT bit-identical to hardware for multiplies,
    #   so a verdict produced here must name the flag.
    #
    # No -cpu: the default core runs everything the ESP parts need. Two cores
    # are NOT interchangeable and a sweep must pin its list -- dsp3400 has no
    # MUL32 at all, and lx106 (the ESP8266 core) has no windowed ABI option.
    need qemu-xtensa
    exec qemu-xtensa "$bin" "$@"
    ;;
  *)
    echo "unknown arch: $arch" >&2
    exit 2
    ;;
esac
