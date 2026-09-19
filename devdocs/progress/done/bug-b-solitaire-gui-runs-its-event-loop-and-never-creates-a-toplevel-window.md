---
summary: "RESOLVED 2026-09-19 (frankH) -- THE SLUG IS WRONG: solitaire_gui DOES create its toplevel. GTK picked the WAYLAND backend (strace: connect to /run/user/1000/wayland-0) because the suite was run from a Wayland desktop seat, and xvfb-run does not stop GTK finding wayland-0. So the window opened on the owner's real desktop while the X-side size check measured an empty Xvfb (0x0, root window 0 children). Fixed with GDK_BACKEND=x11 on every GTK xvfb-run in tools/gui_suite.sh and the Makefile: solitaire 820x640, eliah_ide 1100x700, GUI suite OK. Track T never saw it because testmgr scrubs WAYLAND_DISPLAY from its jobs."
track: B
prio: 65
type: bug
blocked-by: []
status: done
owner: frankH
---

# `solitaire_gui` runs its event loop and never creates a toplevel

Measured 2026-09-19 by frankH, found beside the `--ro-rtti` work and **not
caused by it** — identical with the flag on and off, two suite runs minutes
apart. **Deterministic, 2 of 2. Not a race.**

## The evidence is a probe, not the suite row

The failing row prints `biggest window 0x0`, and **`0x0` is that check's
INITIAL value** (`bw=0 bh=0`), emitted when it finds no window at all — it is
not a window that was found and mismeasured. Probed directly against the
flag-off `/tmp/gui_test_solitaire`, default mode, under xvfb, after 3s:

- the process is **alive**;
- `xwininfo -root -tree` shows the root with **0 children** — the app created
  no X window at all, not even GTK's helper;
- it sits in `poll_schedule_timeout`, state `S`, **0 CPU ticks over 2s**, 5
  sockets open.

So it is idle in an event loop having never created its toplevel.

## Why the suite's other solitaire row PASSES, and why that is not a contradiction

`solitaire_gui (real window)` runs `--gui-smoke`, which **self-quits** and
prints `GUI SMOKE OK`; the suite's own comment says it proves only *"didn't
crash in 400ms"*. The size check runs the app in **DEFAULT** mode. Two rows,
one program, different questions — the passing row does not assert that a
window exists.

## This is a RETURN, not a new shape

`done/bug-gui-pcl-apps-broken-current-stable` records the same behaviour —
*"solitaire ran the loop but never showed its toplevel (FMainForm nil)"*. It is
back, or it never fully left. **Start there rather than from scratch**, and
check whether that fix is carried by the current pin.

## Instrument caveat, recorded by the finder rather than discovered later

There is **no positive control for the size check on this box**: its only other
subject, `eliah_ide`, does not build
(`bug-p-the-address-of-a-method-is-typed-pointer-so-it-cannot-match-a-tmethod-parameter`),
and `life` is not size-checked. So the ROW alone is a guard that cannot be shown
to fail here. **The `xwininfo`/`/proc` probe above does not depend on `xdotool`
and is the evidence to trust.**

## Why it is ranked 65

`solitaire_gui` is a DEMO, and *"have a nice list of working demo's"* is on the
goal list. A demo that starts, consumes no CPU and shows nothing is failing in
the most visible way a demo can.

## Resolution — 2026-09-19 (frankH): the app was fine; the suite measured the wrong display

- **Not a pcl or app defect.** `examples/solitaire_gui` still sets
  `Application.MainForm`, so this is not a return of the July cause.
- **The discriminator was strace, not the X tools.** The process connected to
  `/run/user/1000/wayland-0`. GTK prefers Wayland on a Wayland session, and even
  with `WAYLAND_DISPLAY` unset it finds `wayland-0` in `XDG_RUNTIME_DIR`
  (measured: unsetting it still gave 0 windows). So the window was on the
  owner's desktop, and Xvfb's root had 0 children.
- **Refuted along the way:** the accessibility-bus stall (`NO_AT_BRIDGE=1`, and
  a 30 s wait, both still 0 windows); the widgetset default (the suite's own
  matrix proves default == explicit GTK3).
- **Fix:** `GDK_BACKEND=x11` on every `xvfb-run` of a GTK binary, in
  tools/gui_suite.sh (3 sites) and the Makefile (C GTK rows, the pxx tkinter
  facade rows, and the facade run near the top). Not on `run_gui_expect`, which
  runs "with whatever display happens to exist" on purpose.
- **Both directions checked:**
  - after: GUI suite OK, solitaire 820x640, eliah_ide 1100x700;
  - negative control: the size check's exact logic on a solitaire built WITHOUT
    `Application.MainForm` gives 10x10 (GTK's helper only), which fails
    >=400x300. So the check still catches the July failure.
- **Why Track T never saw it:** testmgr drops `WAYLAND_DISPLAY` and the rest of
  the session family from every job that does not name one. It bites only a
  run from a desktop seat, which is also the case where it puts windows on the
  owner's screen.
- eliah_ide's size check (restored by the TMethod fix, f88effa4a) is now the
  positive control it was meant to be: 1100x700.


## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
