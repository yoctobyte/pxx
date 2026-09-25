#!/usr/bin/env bash
# espide.sh -- start the ESP32 IDE (apps/ide/esp), building it first when the
# binary is missing or older than anything it is compiled from. Arguments go
# through to the IDE:
#
#   ./espide.sh                              opens examples/esp32
#   ./espide.sh examples/esp32/hello-s3      opens that folder
#   ./espide.sh --auto <project> [secs]      detect, build+flash, monitor
#
# Works from any directory: the checkout is found from this script's path.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BIN="$ROOT/apps/ide/esp/espide"
PXX="${PXX_STABLE:-$("$ROOT/tools/pxx_stable.sh")}"

stale=0
if [ ! -x "$BIN" ]; then
  stale=1
elif [ -n "$(find "$ROOT/apps/ide/esp" "$ROOT/apps/ide/garin" "$ROOT/lib/pcl" \
               "$ROOT/lib/rtl" -type f -newer "$BIN" \
               \( -name '*.pas' -o -name '*.inc' -o -name '*.pp' -o -name '*.h' \) \
               -print -quit)" ]; then
  stale=1
elif [ "$(readlink -f "$PXX")" -nt "$BIN" ]; then
  stale=1                       # a new pin
fi
if [ "$stale" = 1 ]; then
  echo "espide.sh: building the IDE (about ten seconds)..." >&2
  "$ROOT/apps/ide/esp/build.sh" >&2 || {
    echo "espide.sh: the IDE did not build; see above" >&2; exit 1; }
fi

# The serial port needs the dialout group. Say how to get it, then start
# anyway: editing and building work without it.
if getent group dialout >/dev/null 2>&1; then
  if ! id -nG | tr ' ' '\n' | grep -qx dialout; then
    if getent group dialout | cut -d: -f4 | tr ',' '\n' | grep -qx "$(id -un)"; then
      echo "espide.sh: you are in the dialout group, but this login predates it: log out and back in to use the board's serial port." >&2
    else
      echo "espide.sh: to use the board's serial port, run: sudo usermod -aG dialout $(id -un)  -- then log out and back in." >&2
    fi
  fi
fi

exec "$BIN" "$@"
