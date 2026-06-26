#!/usr/bin/env bash
#
# demos.sh — build & run PXX example apps. Pick from a menu, or run all the
# batch (non-interactive) demos at once.
#
#     ./demos.sh            # interactive menu
#     ./demos.sh all        # build+run every batch demo
#     ./demos.sh list       # just list them
#
# Uses ./pxx (created by ./install.sh) — falls back to the pinned compiler with
# the library roots if ./pxx is absent.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Demos build with the installed ./pxx. Require install first — the demos need a
# configured compiler (library roots, optional externals), so this stays a
# post-install step rather than something runnable straight from a bare checkout.
if [ ! -x "$ROOT/pxx" ]; then
  echo "demos need the compiler set up first — run:  ./install.sh" >&2
  echo "(it creates ./pxx, then offers to launch these demos)" >&2
  exit 1
fi
PXX=("$ROOT/pxx")

# name | source | kind | description
#   kind: batch (runs to completion) | tty (reads stdin) | gui (needs X/GTK/GL)
DEMOS=(
  "primes|examples/primes/sieve.pas|batch|Sieve of Eratosthenes"
  "sudoku|examples/sudoku/sudoku.pas|batch|Sudoku solver"
  "factorial|examples/bignum/factorial.pas|batch|Big-integer factorial"
  "bigmath|examples/bignum/bigmath.pas|batch|Arbitrary-precision arithmetic"
  "json|examples/json/jsondemo.pas|batch|JSON parse/emit"
  "sat|examples/sat/satdemo.pas|batch|DPLL SAT solver"
  "mathf|examples/mathf/mathdemo.pas|batch|Floating-point math library"
  "life|examples/life/life.pas|tty|Conway's Game of Life (animates; Ctrl-C to stop)"
  "maze|examples/maze/maze.pas|batch|Maze generator"
  "mandelbrot|examples/mandelbrot/mandelbrot.pas|batch|ASCII Mandelbrot set"
  "vm|examples/vm/vmdemo.pas|batch|Tiny bytecode VM"
  "calc|examples/calc/calcdemo.pas|tty|Expression calculator (reads stdin)"
  "lisp|examples/lisp/lispdemo.pas|tty|Lisp interpreter (REPL)"
  "chess|examples/chess/chess.pas|tty|Chess engine (interactive)"
  "adventure|examples/adventure/adventure.pas|tty|Text adventure"
  "2048|examples/g2048/console_2048.pas|tty|2048 in the terminal"
  "solitaire|examples/solitaire/console_solitaire.pas|tty|Klondike solitaire (terminal)"
  "menu|examples/tui/menudemo.pas|tty|TUI menu widgets"
  "triangle|examples/gl/triangle.pas|gui|OpenGL triangle"
  "solitaire-gui|examples/solitaire_gui/solitaire_gui.pas|gui|Solitaire (GUI)"
  "fm|examples/fm/fm.pas|gui|File manager (GTK)"
  "player|examples/player/player.pas|gui|Media player (GTK)"
)

list() {
  printf '\n  %-14s %-6s %s\n' "NAME" "KIND" "DESCRIPTION"
  local i=1 d name kind desc
  for d in "${DEMOS[@]}"; do
    IFS='|' read -r name _ kind desc <<<"$d"
    printf '  %2d) %-10s %-6s %s\n' "$i" "$name" "$kind" "$desc"
    i=$((i+1))
  done
  printf '\n   a) all batch demos     q) quit\n\n'
}

build_run() {
  local src="$1" kind="$2" name="$3" out="/tmp/pxxdemo_$3"
  printf '\n\033[1m-- %s\033[0m  (%s)\n' "$name" "$src"
  if ! "${PXX[@]}" "$src" "$out"; then
    echo "   build FAILED"; return 1
  fi
  case "$kind" in
    gui) echo "   built: $out  (GUI app — run it directly: $out)" ;;
    tty) echo "   running (interactive; Ctrl-C / quit to exit)"; "$out" ;;
    *)   "$out" ;;
  esac
}

run_all_batch() {
  local d name src kind desc ok=0 fail=0
  for d in "${DEMOS[@]}"; do
    IFS='|' read -r name src kind desc <<<"$d"
    [ "$kind" = batch ] || continue
    if build_run "$src" "$kind" "$name"; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done
  printf '\n\033[1mbatch demos: %d ok, %d failed\033[0m\n' "$ok" "$fail"
}

case "${1:-menu}" in
  list) list; exit 0 ;;
  all)  run_all_batch; exit 0 ;;
esac

# interactive menu
while true; do
  list
  read -rp "pick a demo number (or a/q): " sel || exit 0
  case "$sel" in
    q|Q|'') exit 0 ;;
    a|A) run_all_batch ;;
    *[!0-9]*|'') echo "?" ;;
    *)
      idx=$((sel-1))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#DEMOS[@]}" ]; then
        IFS='|' read -r name src kind desc <<<"${DEMOS[$idx]}"
        build_run "$src" "$kind" "$name" || true
      else
        echo "out of range"
      fi
      ;;
  esac
done
