#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# setup.sh — install a PXX release. Run from inside an unpacked release tree
# (the dir containing compiler/, lib/, examples/). Detects the native arch, points
# `compiler/pxx` at the matching binary, and offers to put it on your PATH.
# Libraries (lib/rtl, lib/pcl, compiler/builtin) are found relative to the binary
# (ExeDir), so the tree works in-place from anywhere — no env vars required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
[[ -d compiler ]] || { echo "setup: run from inside an unpacked PXX release (no compiler/ here)"; exit 1; }

case "$(uname -m)" in
  x86_64|amd64)        arch=x86_64 ;;
  i386|i486|i586|i686) arch=i386 ;;
  aarch64|arm64)       arch=aarch64 ;;
  armv7l|armv6l|armhf) arch=arm32 ;;
  *) echo "setup: unsupported host arch '$(uname -m)' (have: x86_64 i386 aarch64 arm32)"; exit 1 ;;
esac

bin="compiler/pxx-$arch"
[[ -x "$bin" ]] || { echo "setup: missing $bin in this release"; exit 1; }
# Every pxx-<arch> is built by the x86_64 compiler with --target=<arch>, and a
# compiler built that way still EMITS x86-64 by default: measured 2026-09-25,
# pxx-aarch64 under qemu turned hello.pas into an x86-64 ELF. A bare symlink
# would hand an aarch64 user a compiler whose output cannot run on their
# machine. So off x86_64, compiler/pxx is a two-line wrapper that names the
# host target; an explicit --target later on the command line still wins (the
# last one does), which selfcheck.sh relies on.
rm -f compiler/pxx
if [[ "$arch" == x86_64 ]]; then
  ln -s "pxx-$arch" compiler/pxx
else
  printf '#!/bin/sh\nexec "$(dirname "$0")/pxx-%s" --target=%s "$@"\n' "$arch" "$arch" > compiler/pxx
  chmod +x compiler/pxx
fi
echo "setup: native arch = $arch -> compiler/pxx -> pxx-$arch"

# Verify the binary actually runs + finds its libs here.
if compiler/pxx --version >/dev/null 2>&1; then
  echo "setup: $(compiler/pxx --version 2>/dev/null | head -1)"
else
  echo "setup: note — 'pxx --version' not available in this build; skipping smoke."
fi

target_dir="${1:-$HOME/.local/bin}"
# No TTY (a script, CI, release.sh's own rehearsal): a failed read left $ans
# empty and the default Y then wrote into the invoking user's ~/.local/bin.
# Only a person at a terminal gets the symlink.
if [[ -t 0 ]]; then
  read -rp "symlink 'pxx' into $target_dir? [Y/n] " ans || true
else
  ans=n
fi
case "${ans:-Y}" in
  n|N) echo "setup: skipped PATH symlink. Run directly via $ROOT/compiler/pxx" ;;
  *)   mkdir -p "$target_dir"
       ln -sf "$ROOT/compiler/pxx" "$target_dir/pxx"
       echo "setup: linked $target_dir/pxx -> $ROOT/compiler/pxx"
       case ":$PATH:" in *":$target_dir:"*) ;; *) echo "setup: add $target_dir to PATH to use 'pxx' directly";; esac ;;
esac

echo "setup: done. Try:  pxx examples/primes/sieve.pas /tmp/sieve && /tmp/sieve"
echo "       verify the install reproduces the release:  ./selfcheck.sh"
