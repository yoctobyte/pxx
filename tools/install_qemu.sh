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

# The binfmt package was renamed between releases: 24.04 (noble) ships
# `qemu-user-static`, 26.04 (resolute) dropped that name and provides the same
# thing as `qemu-user-binfmt`. Asking for the wrong one is a hard apt error
# ("has no installation candidate"), which took this script out on seven's
# 24.04->26.04 upgrade, so resolve the name instead of hardcoding it — borg is
# still on 24.04 and both spellings have to keep working.
# Test the CANDIDATE, not mere existence: on resolute `qemu-user-static` still
# exists as a pure virtual package, so `apt-cache show` (and dpkg-query, and
# apt-cache showpkg) all succeed on it while `apt-get install` still fails with
# "has no installation candidate". Only "Candidate:" tells the two apart —
# a real package names a version, a virtual or absent one gives (none)/empty.
BINFMT_PKG=qemu-user-static
case "$(apt-cache policy "$BINFMT_PKG" 2>/dev/null | awk '/Candidate:/{print $2}')" in
  ''|'(none)') BINFMT_PKG=qemu-user-binfmt ;;
esac

sudo apt-get install -y qemu-user "$BINFMT_PKG" binfmt-support

echo
for q in qemu-i386 qemu-aarch64 qemu-arm qemu-riscv32 qemu-riscv64 qemu-xtensa; do
  if command -v "$q" >/dev/null 2>&1; then
    echo "ok: $q ($("$q" --version | head -n1))"
  else
    echo "MISSING: $q"
  fi
done
