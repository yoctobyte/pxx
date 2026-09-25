#!/usr/bin/env bash
# Headless test gate for the garin core: build bochan (driver) + eduth (validator)
# with the pinned stable compiler and run it. NO lib/pcl on the search path --
# building at all proves garin is render-agnostic. Exit code = verdict.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# tools/pxx_stable.sh: .../pinned in a checkout, compiler/pxx-<arch> in a
# release tarball (which has no stable_linux_amd64/), plus the host --target
# that a cross-built pxx-<arch> needs.
PXX="${PXX_STABLE:-$("$ROOT/tools/pxx_stable.sh")}"
PXXT=()
[ -n "${PXX_STABLE:-}" ] || PXXT=($("$ROOT/tools/pxx_stable.sh" --target-flag))

test -x "$PXX" || { echo "No stable compiler at $PXX" >&2; exit 1; }

"$PXX" "${PXXT[@]}" \
  -Fu"$ROOT/lib/rtl" \
  -Fu"$ROOT/apps/ide/garin" \
  -Fu"$ROOT/apps/ide/eduth" \
  "$ROOT/apps/ide/bochan/main.pas" \
  "$ROOT/apps/ide/bochan/bochan"

# bochan resolves fixtures relative to the repo root.
cd "$ROOT"
exec "$ROOT/apps/ide/bochan/bochan"
