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

if [ "$fail" -ne 0 ]; then
  say "GUI suite finished with some failures (compiler bugs pending)."
  exit 1
else
  say "GUI suite OK"
  exit 0
fi
