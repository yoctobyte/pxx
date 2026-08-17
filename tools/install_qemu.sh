#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Install the QEMU user-mode emulators used by the cross-target test
# environment (see devdocs/progress/*/chore-qemu-test-env.md and
# tools/run_target.sh). Needs sudo.
#
# qemu-user runs a single foreign-architecture Linux binary by translating
# its syscalls onto the host kernel — no VM, no kernel image, fast enough
# for the full test suite and fixedpoint gates. PXX test binaries are
# static and syscall-only, the ideal case (no target sysroot needed).
# qemu-user-static + binfmt registration additionally lets the kernel
# exec foreign binaries directly (./prog just works).
# no-vendor-tracked: out-of-scope — installs SYSTEM packages via apt-get. Nothing
# is written into the working tree, so it cannot put third-party source under a
# tracked path. Declared rather than inferred: tools/check_no_vendor_tracked.sh
# treats every tools/install_*.sh as in-scope until it says otherwise, because a
# heuristic for "does this fetch into the repo?" can only guess, and its first
# draft guessed wrong about install_externals.sh and silently protected nothing.
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
