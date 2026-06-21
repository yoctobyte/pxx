#!/usr/bin/env bash
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
ln -sf "pxx-$arch" compiler/pxx
echo "setup: native arch = $arch -> compiler/pxx -> pxx-$arch"

# Verify the binary actually runs + finds its libs here.
if compiler/pxx --version >/dev/null 2>&1; then
  echo "setup: $(compiler/pxx --version 2>/dev/null | head -1)"
else
  echo "setup: note — 'pxx --version' not available in this build; skipping smoke."
fi

target_dir="${1:-$HOME/.local/bin}"
read -rp "symlink 'pxx' into $target_dir? [Y/n] " ans || true
case "${ans:-Y}" in
  n|N) echo "setup: skipped PATH symlink. Run directly via $ROOT/compiler/pxx" ;;
  *)   mkdir -p "$target_dir"
       ln -sf "$ROOT/compiler/pxx" "$target_dir/pxx"
       echo "setup: linked $target_dir/pxx -> $ROOT/compiler/pxx"
       case ":$PATH:" in *":$target_dir:"*) ;; *) echo "setup: add $target_dir to PATH to use 'pxx' directly";; esac ;;
esac

echo "setup: done. Try:  pxx examples/primes/sieve.pas /tmp/sieve && /tmp/sieve"
echo "       verify the install reproduces the release:  ./selfcheck.sh"
