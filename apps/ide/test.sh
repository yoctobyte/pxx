#!/usr/bin/env bash
# Headless test gate for the garin core: build bochan (driver) + eduth (validator)
# with the pinned stable compiler and run it. NO lib/pcl on the search path --
# building at all proves garin is render-agnostic. Exit code = verdict.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PXX="${PXX_STABLE:-$ROOT/stable_linux_amd64/default/pinned}"

test -x "$PXX" || { echo "No stable compiler at $PXX" >&2; exit 1; }

"$PXX" \
  -Fu"$ROOT/lib/rtl" \
  -Fu"$ROOT/apps/ide/garin" \
  -Fu"$ROOT/apps/ide/eduth" \
  "$ROOT/apps/ide/bochan/main.pas" \
  "$ROOT/apps/ide/bochan/bochan"

# bochan resolves fixtures relative to the repo root.
cd "$ROOT"
exec "$ROOT/apps/ide/bochan/bochan"
