#!/usr/bin/env bash
#
# demos.sh — build & run PXX example apps. Pick from a menu, or build the whole
# set at once (batch demos run; tty/gui/net are built for you to launch).
#
#     ./demos.sh            # interactive menu
#     ./demos.sh all        # build every demo (runs the batch ones)
#     ./demos.sh list       # just list them
#
# Uses ./pxx (created by ./install.sh) — falls back to the pinned compiler with
# the library roots if ./pxx is absent.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Built binaries land in an in-checkout, gitignored dir (same as `make demos`),
# so they are easy to find and re-run instead of buried in /tmp. Override with
# DEMO_OUT=/tmp/... for a throwaway build.
BUILD="${DEMO_OUT:-$ROOT/build/demos}"
mkdir -p "$BUILD"

# Demos build with the installed ./pxx. Require install first — the demos need a
# configured compiler (library roots, optional externals), so this stays a
# post-install step rather than something runnable straight from a bare checkout.
if [ ! -x "$ROOT/pxx" ]; then
  echo "demos need the compiler set up first — run:  ./install.sh" >&2
  echo "(it creates ./pxx, then offers to launch these demos)" >&2
  exit 1
fi
PXX=("$ROOT/pxx")

# Example dirs that hold a `unit` (klondike, engine, g2048) — added to the search
# path so a demo can use an engine from a SIBLING dir (console_solitaire uses
# solitaire_gui/klondike). Same-dir units already resolve on their own.
EXFU=()
while IFS= read -r d; do EXFU+=("-Fu$d"); done < <(
  grep -rlE '^[[:space:]]*unit[[:space:]]' "$ROOT/examples" --include='*.pas' 2>/dev/null \
    | grep -v '/esp32/' | xargs -r -n1 dirname | sort -u)

# name | source | kind | description
#   kind: batch (runs to completion) | tty (reads stdin) | gui (needs X/GTK/GL)
#         | net (needs network — built, not auto-run)
DEMOS=(
  "primes|examples/primes/sieve.pas|batch|Sieve of Eratosthenes"
  "sudoku|examples/sudoku/sudoku.pas|batch|Sudoku solver"
  "sudoku-game|examples/sudoku/sudoku_game.pas|tty|Interactive Sudoku game"
  "factorial|examples/bignum/factorial.pas|batch|Big-integer factorial"
  "bigmath|examples/bignum/bigmath.pas|batch|Arbitrary-precision arithmetic"
  "json|examples/json/jsondemo.pas|batch|JSON parse/emit"
  "sat|examples/sat/satdemo.pas|batch|DPLL SAT solver"
  "mathf|examples/mathf/mathdemo.pas|batch|Floating-point math library"
  "life|examples/life/life.pas|tty|Conway's Game of Life (animates; Ctrl-C to stop)"
  "maze|examples/maze/maze.pas|batch|Maze generator"
  "mandelbrot|examples/mandelbrot/mandelbrot.pas|batch|ASCII Mandelbrot set"
  "raytracer|examples/raytracer/raytracer.pas|batch|Ray tracer (renders an image)"
  "vm|examples/vm/vmdemo.pas|batch|Tiny bytecode VM"
  "calc|examples/calc/calcdemo.pas|tty|Expression calculator (reads stdin)"
  "lisp|examples/lisp/lispdemo.pas|tty|Lisp interpreter (REPL)"
  "chess|examples/chess/chess.pas|tty|Chess engine (interactive)"
  "adventure|examples/adventure/adventure.pas|tty|Text adventure"
  "2048|examples/g2048/console_2048.pas|tty|2048 in the terminal"
  "solitaire|examples/solitaire/console_solitaire.pas|tty|Klondike solitaire (terminal)"
  "menu|examples/tui/menudemo.pas|tty|TUI menu widgets"
  "httpdemo|examples/net/httpdemo.pas|net|Async HTTP client (needs network)"
  "triangle|examples/gl/triangle.pas|gui|OpenGL triangle"
  "solitaire-gui|examples/solitaire_gui/solitaire_gui.pas|gui|Solitaire (GUI)"
  "raytracer-gui|examples/raytracer/raytracer_gui.pas|gui|Ray tracer (GUI)"
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
  printf '\n   a) build all demos      q) quit\n\n'
}

build_run() {
  local src="$1" kind="$2" name="$3" out="$BUILD/$3"
  printf '\n\033[1m-- %s\033[0m  (%s)\n' "$name" "$src"
  if ! "${PXX[@]}" "${EXFU[@]}" "$src" "$out"; then
    echo "   build FAILED"; return 1
  fi
  case "$kind" in
    gui) echo "   built: $out  (GUI app — run it directly: $out)" ;;
    net) echo "   built: $out  (needs network — run it directly: $out)" ;;
    tty) echo "   running (interactive; Ctrl-C / quit to exit)"; "$out" ;;
    *)   "$out" ;;
  esac
}

# Build EVERY demo (all kinds). Run the batch ones (they complete on their own);
# tty demos read stdin and gui demos need a display, so those are built-only here
# and printed for the user to launch. "all batch demos" it is not — the point is a
# one-shot build of the whole set.
run_all() {
  local d name src kind desc built=0 fail=0 ran=0 out
  for d in "${DEMOS[@]}"; do
    IFS='|' read -r name src kind desc <<<"$d"
    out="$BUILD/$name"
    printf '\n\033[1m-- %s\033[0m  (%s) [%s]\n' "$name" "$src" "$kind"
    if ! "${PXX[@]}" "${EXFU[@]}" "$src" "$out"; then
      echo "   build FAILED"; fail=$((fail+1)); continue
    fi
    built=$((built+1))
    if [ "$kind" = batch ]; then
      "$out"; ran=$((ran+1))
    else
      echo "   built: $out  ($kind — run it directly)"
    fi
  done
  printf '\n\033[1mdemos: %d built, %d failed  (%d batch ran; tty/gui built-only)\033[0m\n' \
    "$built" "$fail" "$ran"
}

case "${1:-menu}" in
  list) list; exit 0 ;;
  all)  run_all; exit 0 ;;
esac

# interactive menu
while true; do
  list
  read -rp "pick a demo number (or a/q): " sel || exit 0
  case "$sel" in
    q|Q|'') exit 0 ;;
    a|A) run_all ;;
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
