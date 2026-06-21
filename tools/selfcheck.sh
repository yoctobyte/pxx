#!/usr/bin/env bash
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
PXX="compiler/pxx"
SRC="compiler/compiler.pas"
[[ -x "$PXX" ]] || { echo "selfcheck: no $PXX — run ./setup.sh first"; exit 1; }
[[ -f "$SRC" ]] || { echo "selfcheck: this release omits compiler source ($SRC) — cannot self-verify"; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0

echo "== check 1: self-fixedpoint (determinism on this host) =="
"$PXX" "$SRC" "$tmp/gen1" >/dev/null
"$tmp/gen1" "$SRC" "$tmp/gen2" >/dev/null
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
    "$PXX" --target="$t" "$SRC" "$tmp/out-$t" >/dev/null
    got="$(sha256sum "$tmp/out-$t" | awk '{print $1}')"
    if [[ "$got" == "$want" ]]; then echo "  OK  $t reproduces"; else echo "  FAIL $t: $got != $want"; fail=1; fi
  done < MANIFEST.sha256
else
  echo "  SKIP no MANIFEST.sha256 (untagged / source-only tree) — determinism-only"
fi

[[ $fail -eq 0 ]] && { echo "selfcheck: PASS"; exit 0; } || { echo "selfcheck: FAIL"; exit 1; }
