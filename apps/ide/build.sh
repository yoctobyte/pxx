#!/usr/bin/env bash
# Build Eliah (GTK face) with the pinned stable compiler. Track B: never rebuilds
# the compiler.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PXX="${PXX_STABLE:-$ROOT/stable_linux_amd64/default/pinned}"

test -x "$PXX" || { echo "No stable compiler at $PXX" >&2; exit 1; }

"$PXX" \
  -Fu"$ROOT/lib/pcl" \
  -Fu"$ROOT/lib/rtl" \
  -Fu"$ROOT/apps/ide/garin" \
  "$ROOT/apps/ide/eliah/main.pas" \
  "$ROOT/apps/ide/eliah/eliah"

echo "built: apps/ide/eliah/eliah"
