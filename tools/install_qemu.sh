#!/usr/bin/env sh
# Install the QEMU user-mode emulators used by the cross-target test
# environment (see docs/progress/*/chore-qemu-test-env.md and
# tools/run_target.sh). Needs sudo.
#
# qemu-user runs a single foreign-architecture Linux binary by translating
# its syscalls onto the host kernel — no VM, no kernel image, fast enough
# for the full test suite and fixedpoint gates. PXX test binaries are
# static and syscall-only, the ideal case (no target sysroot needed).
# qemu-user-static + binfmt registration additionally lets the kernel
# exec foreign binaries directly (./prog just works).
set -eu

sudo apt-get install -y qemu-user qemu-user-static binfmt-support

echo
for q in qemu-i386 qemu-aarch64 qemu-arm qemu-riscv32 qemu-riscv64; do
  if command -v "$q" >/dev/null 2>&1; then
    echo "ok: $q ($("$q" --version | head -n1))"
  else
    echo "MISSING: $q"
  fi
done
