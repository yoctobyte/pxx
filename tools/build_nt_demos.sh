#!/bin/sh
# Build pxx demos as Windows x64 programs (--os=windows), for a
# live image that boots ReactOS or Linux+Wine (pixx). They draw with VT
# sequences; on a console without VT processing (ReactOS) the runtime
# carries them out itself (compiler/builtin/winabi.pas, ConWriteVT).
# klondike.exe is the GUI solitaire (PCL over user32/gdi32,
# lib/pcl/win32widgets.pas).
#
# usage: tools/build_nt_demos.sh OUTDIR [COMPILER]
#   OUTDIR    receives the .exe files and a DEMOS.txt listing them
#   COMPILER  defaults to compiler/pascal26 of this checkout
set -eu
out=${1:?usage: tools/build_nt_demos.sh OUTDIR [COMPILER]}
here=$(cd "$(dirname "$0")/.." && pwd)
pxx=${2:-$here/compiler/pascal26}
export PXX_HOME=${PXX_HOME:-$here}
mkdir -p "$out"
cd "$here"
build() {   # name, source, extra flags...
  n=$1; src=$2; shift 2
  "$pxx" --os=windows "$@" "$src" "$out/$n.exe" >/dev/null
  printf '%-18s %s\n' "$n.exe" "$src" >> "$out/DEMOS.txt"
}
: > "$out/DEMOS.txt"
build solitaire  examples/solitaire/console_solitaire.pas -Fuexamples/solitaire_gui
build klondike   examples/solitaire_gui/solitaire_gui.pas -Fuexamples/solitaire_gui
build 2048       examples/g2048/console_2048.pas
build chess      examples/chess/chess.pas
build menudemo   examples/tui/menudemo.pas
build mandelbrot examples/mandelbrot/mandelbrot.pas
printf 'pxx %s\n' "$(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo unknown)" >> "$out/DEMOS.txt"
echo "built: $(ls "$out" | grep -c '\.exe$') demos in $out"
