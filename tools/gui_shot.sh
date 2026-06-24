#!/usr/bin/env bash
# gui_shot.sh — capture a screenshot of a PCL/GTK app on a private Xvfb display,
# never touching the real screen (:0). Solves the foreground-grab + flaky-capture
# pain documented in docs/developer/gui-testing.md.
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

DISP="${GUI_SHOT_DISPLAY:-:99}"
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

dispnum="${DISP#:}"

xvfb_alive() { DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1; }

start_xvfb() {
  Xvfb "$DISP" -screen 0 "$SCREEN" >/tmp/gui_shot_xvfb.log 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.4
    xvfb_alive && return 0
  done
  return 1
}

restart_xvfb() {
  pkill -9 -f "Xvfb $DISP" 2>/dev/null
  pkill -9 -f "Xvfb ${DISP} " 2>/dev/null
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

# A real PCL window compresses to well over this; a blank frame is ~1-3 KB.
BLANK_MAX=4000

ensure_xvfb
run_app
sleep "$SETTLE"
SZ="$(grab)"

if [ "${SZ:-0}" -le "$BLANK_MAX" ]; then
  # blank — the display is likely wedged; restart it and try once more, giving
  # the freshly-started server + app extra time to map.
  kill_app
  FRESH=1 ensure_xvfb
  sleep 1
  run_app
  sleep "$(( ${SETTLE%.*} * 2 + 3 ))"
  SZ="$(grab)"
fi

kill_app

if [ "${SZ:-0}" -le "$BLANK_MAX" ]; then
  echo "gui_shot: capture looks blank (${SZ}B) -> $OUT" >&2
  exit 1
fi
echo "gui_shot: $OUT (${SZ}B) on $DISP"
