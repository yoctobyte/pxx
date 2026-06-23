#!/usr/bin/env bash
# Track B GUI test suite (Pxx Component Library).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PXX_STABLE="${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}"

fail=0

say() {
  printf '%s\n' "$*"
}

run_gui_test() {
  local name="$1"
  local src="$ROOT/test/gui/$name.pas"
  local out="/tmp/gui_test_$name"
  local log="/tmp/gui_test_$name.log"
  
  if ! "$PXX_STABLE" -Fulib/pcl "$src" "$out" >"$log" 2>&1; then
    say "FAIL  $name -- compile: $(tail -1 "$log")"
    fail=1
    return
  fi
  
  if ! "$out" >"$log" 2>&1; then
    say "FAIL  $name -- runtime: $(tail -1 "$log")"
    fail=1
    return
  fi
  
  say "OK    $name"
}

say "=== running GUI test suite (PCL) ==="
run_gui_test test_gtk_ffi
run_gui_test test_pcl_click
run_gui_test test_pcl_event_rtti
run_gui_test test_pcl_lfm
run_gui_test test_pcl_widgets
run_gui_test test_pcl_drawing
run_gui_test test_pcl_menus
run_gui_test test_pcl_input

# Solitaire GUI demo (engine in examples/solitaire_gui): compile + headless
# --smoke run (renders the board + a few engine moves, prints SMOKE OK).
solitaire_smoke() {
  local src="$ROOT/examples/solitaire_gui/solitaire_gui.pas"
  local out="/tmp/gui_test_solitaire" log="/tmp/gui_test_solitaire.log"
  if ! "$PXX_STABLE" -Fulib/pcl -Fuexamples/solitaire_gui "$src" "$out" >"$log" 2>&1; then
    say "FAIL  solitaire_gui -- compile: $(tail -1 "$log")"; fail=1; return
  fi
  if [ "$("$out" --smoke 2>"$log" | tail -1)" != "SMOKE OK" ]; then
    say "FAIL  solitaire_gui -- smoke: $(tail -1 "$log")"; fail=1; return
  fi
  say "OK    solitaire_gui"
}
solitaire_smoke

# Eliah IDE (apps/ide/eliah): compile + headless --smoke (tree populates, opens a
# file in the editor, compiles it, prints SMOKE OK).
eliah_smoke() {
  local src="$ROOT/apps/ide/eliah/main.pas"
  local out="$ROOT/apps/ide/eliah/eliah" log="/tmp/gui_test_eliah.log"
  if ! "$PXX_STABLE" -Fulib/pcl -Fulib/rtl -Fuapps/ide/garin "$src" "$out" >"$log" 2>&1; then
    say "FAIL  eliah_ide -- compile: $(tail -1 "$log")"; fail=1; return
  fi
  if [ "$(cd "$ROOT" && "$out" --smoke 2>"$log" | tail -1)" != "SMOKE OK" ]; then
    say "FAIL  eliah_ide -- smoke: $(tail -1 "$log")"; fail=1; return
  fi
  say "OK    eliah_ide"
}
eliah_smoke

if [ "$fail" -ne 0 ]; then
  say "GUI suite finished with some failures (compiler bugs pending)."
  exit 1
else
  say "GUI suite OK"
  exit 0
fi
