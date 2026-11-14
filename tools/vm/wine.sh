#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# wine.sh -- run a --os=windows executable under Wine (the test-windows target).
#
#   tools/vm/wine.sh <prog.exe> [args...]
#
# The prefix is $PXX_WINEPREFIX, else /data/vm/wine when /data exists (plexus
# keeps VM state there), else ~/.wine-pxx. The first run creates it, which
# takes a minute and prints Wine's own setup noise; WINEDEBUG=-all silences
# Wine's diagnostics after that, so stdout and stderr are the program's.
# Exits with the program's status. feature-port-windows-pe
if [ -n "$PXX_WINEPREFIX" ]; then WINEPREFIX=$PXX_WINEPREFIX
elif [ -d /data ]; then WINEPREFIX=/data/vm/wine
else WINEPREFIX=$HOME/.wine-pxx
fi
export WINEPREFIX
export WINEDEBUG=-all
# A crash outside the program's own handling must end the process, not start
# winedbg (which waits for a terminal and hangs the test until the timeout).
export WINEDLLOVERRIDES="winedbg.exe=d${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
command -v wine64 >/dev/null 2>&1 || { echo "wine.sh: wine64 is not installed" >&2; exit 125; }
exec timeout 120 wine64 "$@"
