#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# selfcheck.sh — post-install / hardware-bringup check. Run from inside an unpacked
# release tree (next to compiler/, lib/, MANIFEST.sha256).
#
# Two checks (see feature-release-packaging):
#   1. self-fixedpoint (native): the binary compiles the compiler twice; gen1==gen2.
#      Determinism on THIS silicon/kernel. Needs no manifest — always runs.
#   2. reproduce-all-targets vs MANIFEST.sha256: this host rebuilds every shipped
#      target binary and the hashes must match the release manifest. Host-independent
#      codegen => any host reproduces every target. Skipped (not failed) if no manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
SRC="compiler/compiler.pas"
# THE HOST'S OWN BINARY, found here rather than through a compiler/pxx that a
# separate setup step had to create first: the README's tarball sequence is
# ./install.sh then ./selfcheck.sh, and this used to stop with "no compiler/pxx
# -- run ./setup.sh first" (measured 2026-09-25). A pxx-<arch> built by the
# x86-64 compiler still EMITS x86-64 by default, so off x86_64 it is run with
# the host target named; check 2's explicit --target comes later on the command
# line and wins, because the last --target does.
case "$(uname -m)" in
  x86_64|amd64)        arch=x86_64 ;;
  i386|i486|i586|i686) arch=i386 ;;
  aarch64|arm64)       arch=aarch64 ;;
  armv7l|armv6l|armhf) arch=arm32 ;;
  *) echo "selfcheck: unsupported host arch '$(uname -m)' (have: x86_64 i386 aarch64 arm32)"; exit 1 ;;
esac
[[ -x "compiler/pxx-$arch" ]] || { echo "selfcheck: no compiler/pxx-$arch in this release"; exit 1; }
HOSTT=()
[[ "$arch" == x86_64 ]] || HOSTT=("--target=$arch")
PXX=("compiler/pxx-$arch" "${HOSTT[@]}")
[[ -f "$SRC" ]] || { echo "selfcheck: this release omits compiler source ($SRC) — cannot self-verify"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

echo "== check 1: self-fixedpoint (determinism on this host) =="
"${PXX[@]}" "$SRC" "$tmp/gen1" >/dev/null
# gen1 is a compiler built BY a cross-built binary, so it too defaults to
# x86-64: without the host target, gen2 would be an x86-64 binary and could
# never equal an aarch64 gen1.
"$tmp/gen1" "${HOSTT[@]}" "$SRC" "$tmp/gen2" >/dev/null
if cmp -s "$tmp/gen1" "$tmp/gen2"; then
  echo "  OK  gen1 == gen2"
else
  echo "  FAIL gen1 != gen2 — this host miscompiles or is non-deterministic"; fail=1
fi

echo "== check 2: reproduce shipped targets (bit compatibility) =="
if [[ -f MANIFEST.sha256 ]]; then
  while read -r want path; do
    [[ "$path" == compiler/pxx-* ]] || continue
    t="${path#compiler/pxx-}"
    "${PXX[@]}" --target="$t" "$SRC" "$tmp/out-$t" >/dev/null
    got="$(sha256sum "$tmp/out-$t" | awk '{print $1}')"
    if [[ "$got" == "$want" ]]; then echo "  OK  $t reproduces"; else echo "  FAIL $t: $got != $want"; fail=1; fi
  done < MANIFEST.sha256
else
  echo "  SKIP no MANIFEST.sha256 (untagged / source-only tree) — determinism-only"
fi

[[ $fail -eq 0 ]] && { echo "selfcheck: PASS"; exit 0; } || { echo "selfcheck: FAIL"; exit 1; }
