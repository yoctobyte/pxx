#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Cross-target differential over the lib tests.
#
# WHY THIS EXISTS. `make lib-test` runs x86-64 ONLY, and Track T's cross matrix
# does not run the lib tests at all -- so nothing in the tree executes lib/rtl
# on a 32-bit target. The first run of this script found
# bug-a-virtual-method-int64-in-and-out-32bit (a virtual method taking AND
# returning an Int64 returns garbage on arm32/riscv32 and crashes on i386,
# which is TStream.Position in the RTL, and riscv32 is ESP32).
#
# The oracle is the x86-64 run of the same binary's source: lib-test already
# proves it correct there, so any cross target that prints something else is
# either a codegen bug or an environment artifact.
#
# CAVEAT, and it matters: this runs under qemu-user, which is not a faithful
# host for threads and some syscalls. A network- or thread-using test differing
# is NOT by itself evidence -- reduce it to something syscall-free before
# believing it. Compute-only divergences are the trustworthy ones.
#
# Usage: tools/lib_cross_sweep.sh   (no rebuild; uses the pinned stable)
set -u
cd /home/rene/frank2
PX="${PXX_STABLE:-./stable_linux_amd64/default/pinned}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
for f in test/lib_*.pas; do
  b=$(basename "$f" .pas)
  $PX -Fulib/rtl "$f" "$OUT/${b}.x64" >/dev/null 2>&1 || { echo "SKIP $b (no native build)"; continue; }
  ref=$(timeout 60 "$OUT/${b}.x64" 2>&1); rrc=$?
  # riscv32 is included because it is ESP32's core: a bug that only shows on a
  # 32-bit RISC target is a bug on the hardware the project is aiming at.
  for tgt in i386 arm32 aarch64 riscv32; do
    case $tgt in
      i386)    q=qemu-i386;;
      arm32)   q=qemu-arm;;
      aarch64) q=qemu-aarch64;;
      riscv32) q=qemu-riscv32;;
    esac
    command -v "$q" >/dev/null || continue
    if ! $PX --target=$tgt -Fulib/rtl "$f" "$OUT/${b}.$tgt" >/dev/null 2>&1; then
      echo "BUILDFAIL $b $tgt"; continue
    fi
    got=$(timeout 60 $q "$OUT/${b}.$tgt" 2>&1); grc=$?
    if [ "$got" != "$ref" ]; then
      nd=$(diff <(printf '%s\n' "$ref") <(printf '%s\n' "$got") | grep -c '^<')
      echo "DIFF $b $tgt  ($nd lines; rc $rrc vs $grc)"
      diff <(printf '%s\n' "$ref") <(printf '%s\n' "$got") | grep '^[<>]' | head -4 | sed 's/^/      /'
    fi
  done
done
echo "=== sweep done ==="
