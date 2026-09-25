#!/usr/bin/env bash
# Build the ESP32 face (apps/ide/esp/espide) with the pinned stable compiler,
# the same way apps/ide/build.sh builds eliah -- see that script for why the
# -Fu roots come before the GTK include root.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PXX="${PXX_STABLE:-$("$ROOT/tools/pxx_stable.sh")}"
PXXT=()
[ -n "${PXX_STABLE:-}" ] || PXXT=($("$ROOT/tools/pxx_stable.sh" --target-flag))

test -x "$PXX" || { echo "No stable compiler at $PXX" >&2; exit 1; }

GTK3_INC="$(pkg-config --cflags-only-I gtk+-3.0 2>/dev/null || true)"
[ -n "$GTK3_INC" ] || GTK3_INC="-I/usr/include/gtk-3.0/"

"$PXX" "${PXXT[@]}" \
  -Fu"$ROOT/lib/pcl" \
  -Fu"$ROOT/lib/rtl" \
  -Fu"$ROOT/apps/ide/garin" \
  $GTK3_INC \
  "$ROOT/apps/ide/esp/main.pas" \
  "$ROOT/apps/ide/esp/espide"

echo "built: apps/ide/esp/espide"
