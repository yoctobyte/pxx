#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Run a PXX-emitted binary for a given CPU target, under QEMU user-mode
# emulation when the host cannot execute it natively.
#
#   tools/run_target.sh <arch> <binary> [args...]
#
# arch: x86_64 | i386 | aarch64 | arm32 | riscv32 | riscv64
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
    if "$bin" "$@" 2>/dev/null; then
      exit 0
    else
      rc=$?
      # ENOEXEC surfaces as 126 from sh; anything else is the program's
      # own exit code — pass it through.
      if [ "$rc" != 126 ]; then exit "$rc"; fi
    fi
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
  *)
    echo "unknown arch: $arch" >&2
    exit 2
    ;;
esac
