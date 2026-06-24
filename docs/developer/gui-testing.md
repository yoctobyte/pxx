# Testing GUI apps (PCL) without grabbing the foreground

PCL apps are real GTK windows. Launching one on the live display `:0` **maps it on
top and steals keyboard/mouse focus** — disruptive when a human is using the
machine, and it makes scripted runs racy. Two rules:

## 1. No screenshot needed → never map a window

Use the headless path. `eliah --smoke` (and the `test/gui/*` construct-only tests)
build the widget tree + run assertions but **do not call `Application.Run`**, so
the window is never shown and nothing grabs the foreground. Prefer these for
logic/exit-code checks:

```
apps/ide/eliah/eliah --smoke          # SMOKE OK, no window
PXX_STABLE=… tools/gui_suite.sh        # construct + smoke, no foreground steal
```

## 2. Screenshot needed → use `tools/gui_shot.sh` (Xvfb wrapper)

**Requires `Xvfb`** (`sudo apt install xvfb`). The wrapper runs the app on a
private framebuffer (`:99`), captures one frame, and kills the app — never
touching the real screen:

```sh
tools/gui_shot.sh OUT.png CMD [ARGS...]
# e.g.
tools/gui_shot.sh /tmp/eliah.png apps/ide/eliah/eliah --split
GUI_SHOT_SIZE=900x600 tools/gui_shot.sh /tmp/narrow.png ./myapp
```

Knobs (env): `GUI_SHOT_SIZE` (default 1100x700), `GUI_SHOT_SETTLE` (2.5s),
`GUI_SHOT_FRESH=1` (kill+restart Xvfb first), `GUI_SHOT_DISPLAY` (`:99`). It
auto-detects a blank/wedged capture and retries once on a fresh Xvfb.

Doing it by hand (what the wrapper automates) — note the **two traps**:

```sh
Xvfb :99 -screen 0 1920x1080x24 &          # once per session
DISPLAY=:99 apps/ide/eliah/eliah &          # renders offscreen, no grab/HID steal
sleep 2
DISPLAY=:99 ffmpeg -y -f x11grab -video_size 1100x700 \
    -i :99+0,0 -frames:v 1 /tmp/shot.png    # MUST be -frames:v 1
```

- **Trap 1:** a bare ffmpeg `-i` (or `-update 1` without `-frames:v 1`) records
  *forever*, wedges the display, and every later grab comes back blank. Always
  `-frames:v 1`.
- **Trap 2:** after many rapid launch/kill cycles the Xvfb display gets wedged
  and grabs go blank (~1-3 KB PNG). A real PCL window is tens of KB. Restart
  Xvfb fresh to recover (the wrapper does this automatically).

Benefits over grabbing `:0`:
- never steals focus / raises over the user's windows;
- full window is captured (no off-screen clipping from WM placement, no overlap
  from terminal/notification popups);
- deterministic size — set the Xvfb screen big enough for the whole window.

`ffmpeg` + PIL are available. There is **no `xdotool`/`wmctrl`** here, so clicks
cannot be scripted — verify *render* via screenshot, interaction logic via
`--smoke`. (If `xdotool`/`wmctrl` get installed later, scripted clicks on `:99`
become possible; update this note.)

## Why not window hints instead

`gtk_window_set_focus_on_map(FALSE)` / `set_accept_focus(FALSE)` would stop the
focus steal but the window still maps on `:0` (visible, possibly over other
windows) and WM placement still clips/overlaps captures. Xvfb is cleaner: the
real screen is never involved. Keep app code free of test-only window hints.

## CRITICAL lesson (do not regress)

`--smoke` validates *logic*, not GTK *rendering*. Headless smoke has shipped real
GUI bugs (dead tree-click, empty list, invisible panes, splitter positions that
don't apply before allocation). **Always screenshot-verify a GUI change** on
Xvfb before declaring it done.
