#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# gui_shot.sh — capture a screenshot of a PCL/GTK app on a private Xvfb display,
# never touching the real screen (:0). Solves the foreground-grab + flaky-capture
# pain documented in devdocs/developer/gui-testing.md.
#
# Usage:
#   tools/gui_shot.sh OUT.png CMD [ARGS...]
#
# Examples:
#   tools/gui_shot.sh /tmp/eliah.png apps/ide/eliah/eliah --split
#   GUI_SHOT_SIZE=900x600 tools/gui_shot.sh /tmp/narrow.png ./myapp
#
# Env knobs:
#   GUI_SHOT_DISPLAY  X display to use            (default :99)
#   GUI_SHOT_SCREEN   Xvfb screen geometry        (default 1920x1080x24)
#   GUI_SHOT_SIZE     capture WxH from top-left   (default 1100x700)
#   GUI_SHOT_SETTLE   seconds to wait before grab (default 2.5)
#   GUI_SHOT_FRESH    1 = kill+restart Xvfb first (default 0)
#
# Why each choice (don't regress):
#   - ffmpeg MUST use `-frames:v 1` (or `-update 1` with it) — a bare `-i`
#     records forever and wedges the display.
#   - the app runs on Xvfb, so it never raises over / steals focus from the user.
#   - a corrupted Xvfb (after many launches) yields a tiny blank PNG; we detect
#     that and retry once on a freshly restarted Xvfb.
set -u

# Display selection. By default we let Xvfb pick a FREE display (-displayfd) so
# two parallel agents never fight over a shared :99 — the old hardcoded default
# meant one agent's pkill/lock-rm killed the other's live Xvfb mid-capture.
# GUI_SHOT_DISPLAY still forces a specific display (back-compat) and is then
# lock-cleaned before start.
DISP="${GUI_SHOT_DISPLAY:-}"
if [ -n "$DISP" ]; then AUTO=0; else AUTO=1; fi
SCREEN="${GUI_SHOT_SCREEN:-1920x1080x24}"
SIZE="${GUI_SHOT_SIZE:-1100x700}"
SETTLE="${GUI_SHOT_SETTLE:-2.5}"
FRESH="${GUI_SHOT_FRESH:-0}"

if [ $# -lt 2 ]; then
  echo "usage: $0 OUT.png CMD [ARGS...]" >&2
  exit 2
fi
OUT="$1"; shift
CMD=( "$@" )

XVFB_PID=""

xvfb_alive() { [ -n "$DISP" ] && DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1; }

# Kill only the Xvfb WE started (by PID) — never pattern-pkill a display number
# that a parallel agent may own.
stop_xvfb() {
  [ -n "$XVFB_PID" ] && kill -9 "$XVFB_PID" 2>/dev/null
  XVFB_PID=""
}
trap 'stop_xvfb' EXIT

start_xvfb() {
  if [ "$AUTO" = "1" ]; then
    # Let Xvfb find a free display and report it on fd 1.
    local fdfile; fdfile="$(mktemp)"
    Xvfb -displayfd 1 -screen 0 "$SCREEN" 1>"$fdfile" 2>/tmp/gui_shot_xvfb.log &
    XVFB_PID=$!
    local n=""
    for _ in $(seq 1 20); do
      n="$(tr -dc '0-9' <"$fdfile")"
      [ -n "$n" ] && break
      sleep 0.3
    done
    rm -f "$fdfile"
    [ -n "$n" ] || return 1
    DISP=":$n"
  else
    rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null   # clear a stale lock for the fixed display
    Xvfb "$DISP" -screen 0 "$SCREEN" >/tmp/gui_shot_xvfb.log 2>&1 &
    XVFB_PID=$!
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.4
    xvfb_alive && return 0
  done
  return 1
}

restart_xvfb() {
  stop_xvfb
  [ "$AUTO" = "1" ] || rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null
  sleep 1
  start_xvfb
}

ensure_xvfb() {
  if [ "$FRESH" = "1" ]; then
    restart_xvfb || { echo "gui_shot: could not start Xvfb $DISP" >&2; exit 1; }
  elif ! xvfb_alive; then
    start_xvfb || { echo "gui_shot: could not start Xvfb $DISP" >&2; exit 1; }
  fi
}

# capture a single frame; returns the file size in bytes (0 on failure)
grab() {
  rm -f "$OUT"
  DISPLAY="$DISP" ffmpeg -y -f x11grab -video_size "$SIZE" \
      -i "${DISP}+0,0" -frames:v 1 "$OUT" >/dev/null 2>&1
  stat -c%s "$OUT" 2>/dev/null || echo 0
}

run_app() {
  DISPLAY="$DISP" "${CMD[@]}" >/tmp/gui_shot_app.log 2>&1 &
  APP_PID=$!
}

kill_app() { kill -9 "$APP_PID" 2>/dev/null; }

# Blank detection: measure the PICTURE, not the file size.
#
# This used to compare the PNG's byte size against BLANK_MAX=4000, on the note
# "a blank frame is ~1-3 KB". That number was true when written and had rotted
# by 2026-08-30 -- but re-deriving it is NOT possible, which is why this is a
# rewrite rather than a new constant. Measured at the default 1100x700 on
# ffmpeg 8.0.1, Xvfb 1920x1080x24:
#
#     empty display          4013 bytes   (five samples, no variance)
#     real xterm window      4068 bytes
#
# Fifty-five bytes apart. The size proxy has no discriminating power left at
# any threshold, because a mostly-empty frame compresses to almost the same
# size whether or not something is drawn in one corner of it. It is also
# resolution- and encoder-dependent by construction, so any replacement number
# would start rotting immediately.
#
# What is measured instead: the share of pixels differing from the frame's most
# common luma, in units of 1/10000. This is a ratio, so it does not move with
# resolution, and it reads decoded pixels, so it does not move with the encoder.
# Same two frames as above:
#
#     empty display             1  /10000   (0.012% -- the mouse cursor, ~60px)
#     real xterm window      1983  /10000   (19.8%)
#
# Three orders of magnitude apart. BLANK_BP sits at 50 (0.5%): 40x above the
# cursor noise floor, and still well under a small dialog (a 200x100 window on
# this canvas is ~260/10000).
#
# If you change this, re-measure both numbers and record them here -- the old
# comment asserted a measurement once, in prose, with nothing that re-checked
# it, and that is precisely how it rotted.
BLANK_BP=50

# Share of non-dominant pixels in $OUT, in 1/10000. Prints 0 when the frame
# cannot be read at all, which is correctly treated as blank below.
blank_bp() {
  ffmpeg -v error -i "$OUT" -vf "scale=256:256:flags=neighbor,format=gray" \
         -f rawvideo - 2>/dev/null \
    | od -An -tu1 -v | tr -s ' ' '\n' | sed '/^$/d' \
    | sort -n | uniq -c | sort -rn \
    | awk 'NR==1 {d=$1} {t+=$1} END {if (t==0) print 0; else printf "%d", (t-d)*10000/t}'
}

ensure_xvfb
run_app
sleep "$SETTLE"
SZ="$(grab)"
BP="$(blank_bp)"

if [ "${BP:-0}" -le "$BLANK_BP" ]; then
  # blank — the display is likely wedged; restart it and try once more, giving
  # the freshly-started server + app extra time to map.
  kill_app
  FRESH=1 ensure_xvfb
  sleep 1
  run_app
  sleep "$(( ${SETTLE%.*} * 2 + 3 ))"
  SZ="$(grab)"
  BP="$(blank_bp)"
fi

kill_app

if [ "${BP:-0}" -le "$BLANK_BP" ]; then
  echo "gui_shot: capture looks blank (${BP}/10000 non-uniform, ${SZ}B) -> $OUT" >&2
  exit 1
fi
echo "gui_shot: $OUT (${SZ}B, ${BP}/10000 non-uniform) on $DISP"
