#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
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

  # Remove the output FIRST. A failed compile must leave nothing runnable, or
  # a previous run's binary gets tested and the suite reports on code that is
  # no longer there.
  rm -f "$out"
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

# Widgetset selection + the sparse (widgetset x OS) matrix
# (feature-pcl-widgetset-select): the default must be byte-identical to an
# explicit gtk3, and every unsupported cell must be a COMPILE error naming the
# reason rather than a silent build.
widgetset_matrix() {
  local src="$ROOT/test/gui/test_pcl_widgets.pas"
  local a="/tmp/gui_ws_default" b="/tmp/gui_ws_gtk3"
  local log="/tmp/gui_ws.log"
  if ! "$PXX_STABLE" -Fulib/pcl -Fulib/rtl "$src" "$a" >"$log" 2>&1; then
    say "FAIL  widgetset -- default build: $(tail -1 "$log")"; fail=1; return
  fi
  if ! "$PXX_STABLE" -dWIDGETSET_GTK3 -Fulib/pcl -Fulib/rtl "$src" "$b" >"$log" 2>&1; then
    say "FAIL  widgetset -- explicit gtk3: $(tail -1 "$log")"; fail=1; return
  fi
  if ! cmp -s "$a" "$b"; then
    say "FAIL  widgetset -- default is not byte-identical to explicit gtk3"; fail=1; return
  fi
  # every unsupported cell refuses, and says why
  local ws
  for ws in WIDGETSET_WIN32 WIDGETSET_QT; do
    if "$PXX_STABLE" "-d$ws" -Fulib/pcl -Fulib/rtl "$src" /tmp/gui_ws_bad >"$log" 2>&1; then
      say "FAIL  widgetset -- -d$ws built instead of refusing"; fail=1; return
    fi
    if ! grep -q 'widgetset' "$log"; then
      say "FAIL  widgetset -- -d$ws refused without naming the widgetset: $(tail -1 "$log")"; fail=1; return
    fi
  done
  say "OK    widgetset selection + matrix"
}

say "=== running GUI test suite (PCL) ==="
widgetset_matrix
run_gui_test test_gtk_ffi
run_gui_test test_pcl_click
run_gui_test test_pcl_event_rtti
run_gui_test test_pcl_lfm
run_gui_test test_pcl_widgets
run_gui_test test_pcl_drawing
run_gui_test test_pcl_menus
run_gui_test test_pcl_input
run_gui_test test_pcl_paned
run_gui_test test_pcl_stream_paned
run_gui_test test_pcl_tabbar

# Solitaire GUI demo (engine in examples/solitaire_gui): compile + headless
# --smoke run (renders the board + a few engine moves, prints SMOKE OK).
solitaire_built=0
solitaire_smoke() {
  local src="$ROOT/examples/solitaire_gui/solitaire_gui.pas"
  local out="/tmp/gui_test_solitaire" log="/tmp/gui_test_solitaire.log"
  rm -f "$out"
  if ! "$PXX_STABLE" -Fulib/pcl -Fuexamples/solitaire_gui "$src" "$out" >"$log" 2>&1; then
    say "FAIL  solitaire_gui -- compile: $(tail -1 "$log")"; fail=1; return
  fi
  solitaire_built=1
  if [ "$("$out" --smoke 2>"$log" | tail -1)" != "SMOKE OK" ]; then
    say "FAIL  solitaire_gui -- smoke: $(tail -1 "$log")"; fail=1; return
  fi
  say "OK    solitaire_gui"
}
solitaire_smoke

# Real-window smokes: map an actual window, run the real gtk event loop, and
# self-quit from a g_timeout (--gui-smoke). Needs a display -> xvfb-run; every
# invocation is timeout-bounded so a missing self-quit can never hang CI.
have_xvfb() { command -v xvfb-run >/dev/null 2>&1; }

gui_window_smoke() {
  local name="$1" bin="$2" expect="$3"
  local log="/tmp/gui_test_${name}_win.log"
  if ! have_xvfb; then
    say "SKIP  $name (real window) -- xvfb-run not installed"
    return
  fi
  if [ "$(timeout 30 xvfb-run -a "$bin" --gui-smoke 2>"$log" | tail -1)" != "$expect" ]; then
    say "FAIL  $name -- real-window smoke: $(tail -1 "$log")"; fail=1; return
  fi
  say "OK    $name (real window)"
}

if [ "$solitaire_built" = "1" ]; then
  gui_window_smoke solitaire_gui /tmp/gui_test_solitaire "GUI SMOKE OK"
fi

# Real-window ASSERTION: the --gui-smoke line only proves "didn't crash in 400ms";
# it says nothing about a window actually mapping. Two real regressions slipped
# past it (bug-gui-pcl-apps-broken-current-stable): eliah threw at startup, and
# solitaire ran the loop but never showed its toplevel (FMainForm nil), yet
# --gui-smoke still printed OK. This launches the app in its DEFAULT mode (the real
# Application.Run, no self-quit), grabs the BIGGEST window owned by the pid, and
# asserts it realizes to a real size. GTK always maps a tiny (10x10/20x20) helper
# window, so a name/first match is worthless -- pick the largest by area and ignore
# the helper. A startup exception leaves NO big window, so this catches crashes too.
have_xdotool() { command -v xdotool >/dev/null 2>&1; }

gui_realwindow() {
  local name="$1" bin="$2" minw="$3" minh="$4"; shift 4
  local log="/tmp/gui_test_${name}_realwin.log"
  if ! have_xvfb; then say "SKIP  $name (real window size) -- xvfb-run not installed"; return; fi
  if ! have_xdotool; then say "SKIP  $name (real window size) -- xdotool not installed"; return; fi
  local geo
  geo="$(timeout 30 xvfb-run -a bash -c '
    bin="$1"; shift
    "$bin" "$@" &
    p=$!
    for _ in $(seq 1 20); do
      [ -n "$(xdotool search --pid "$p" 2>/dev/null)" ] && break
      sleep 0.3
    done
    sleep 1
    best=0 bw=0 bh=0
    for w in $(xdotool search --pid "$p" 2>/dev/null); do
      g="$(xdotool getwindowgeometry "$w" 2>/dev/null | grep -oE "[0-9]+x[0-9]+" | head -1)"
      [ -n "$g" ] || continue
      ww="${g%x*}"; hh="${g#*x}"; a=$((ww*hh))
      if [ "$a" -gt "$best" ]; then best=$a; bw=$ww; bh=$hh; fi
    done
    kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
    printf "%sx%s\n" "$bw" "$bh"
  ' _ "$bin" "$@" 2>"$log")" || true
  local gw="${geo%x*}" gh="${geo#*x}"
  if [ -z "$gw" ] || [ "${gw:-0}" -lt "$minw" ] || [ "${gh:-0}" -lt "$minh" ]; then
    say "FAIL  $name -- no real toplevel (biggest window ${geo:-none}, need >=${minw}x${minh}; startup crash or unshown form)"
    fail=1; return
  fi
  say "OK    $name (real window ${geo})"
}

if [ "$solitaire_built" = "1" ]; then
  gui_realwindow solitaire_gui /tmp/gui_test_solitaire 400 300
else
  say "SKIP  solitaire_gui (window checks) -- it did not build"
fi

# life: the original real-window self-closing GUI run (its --smoke maps a GTK
# window and auto-quits after ~9 generations) — the reference case.
life_smoke() {
  local src="$ROOT/examples/life/life.pas"
  local out="/tmp/gui_test_life" log="/tmp/gui_test_life.log"
  rm -f "$out"
  if ! "$PXX_STABLE" -Fulib/pcl -Fulib/rtl "$src" "$out" >"$log" 2>&1; then
    say "FAIL  life -- compile: $(tail -1 "$log")"; fail=1; return
  fi
  if ! have_xvfb; then
    say "SKIP  life (real window) -- xvfb-run not installed"
    return
  fi
  if ! timeout 30 xvfb-run -a "$out" --smoke >"$log" 2>&1; then
    say "FAIL  life -- real-window smoke: $(tail -1 "$log")"; fail=1; return
  fi
  say "OK    life (real window)"
}
life_smoke

# Eliah IDE (apps/ide/eliah): compile + headless --smoke (tree populates, opens a
# file in the editor, compiles it, prints SMOKE OK).
eliah_built=0
eliah_smoke() {
  local src="$ROOT/apps/ide/eliah/main.pas"
  local out="$ROOT/apps/ide/eliah/eliah" log="/tmp/gui_test_eliah.log"
  # eliah's binary lives in the TREE, not /tmp, so a stale one survives for
  # weeks. Before this, a failed compile was followed by two window checks
  # against the OLD binary and the suite printed
  #   FAIL  eliah_ide -- compile: ...
  #   OK    eliah_ide (real window 1100x727)
  # two lines apart -- a red that reads half-green.
  rm -f "$out"
  if ! "$PXX_STABLE" -Fulib/pcl -Fulib/rtl -Fuapps/ide/garin "$src" "$out" >"$log" 2>&1; then
    say "FAIL  eliah_ide -- compile: $(tail -1 "$log")"; fail=1; return
  fi
  eliah_built=1
  if [ "$(cd "$ROOT" && "$out" --smoke 2>"$log" | tail -1)" != "SMOKE OK" ]; then
    say "FAIL  eliah_ide -- smoke: $(tail -1 "$log")"; fail=1; return
  fi
  say "OK    eliah_ide"
}
eliah_smoke
if [ "$eliah_built" = "1" ]; then
  gui_window_smoke eliah_ide "$ROOT/apps/ide/eliah/eliah" "GUI SMOKE OK"
fi
# eliah is the app that regressed (startup EInOutError under the {$I+} flip); a
# real-window assertion is exactly what would have caught it -- a crash leaves no
# 'Eliah - IDE' toplevel.
if [ "$eliah_built" = "1" ]; then
  gui_realwindow eliah_ide "$ROOT/apps/ide/eliah/eliah" 800 500
else
  say "SKIP  eliah_ide (window checks) -- it did not build"
fi

if [ "$fail" -ne 0 ]; then
  say "GUI suite finished with some failures (compiler bugs pending)."
  exit 1
else
  say "GUI suite OK"
  exit 0
fi
