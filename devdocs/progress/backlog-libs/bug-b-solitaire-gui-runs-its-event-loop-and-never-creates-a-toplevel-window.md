---
summary: "solitaire_gui in default mode creates NO X window at all — root has 0 children while the process sits idle in poll; deterministic 2/2, same shape as the closed bug-gui-pcl-apps-broken-current-stable (FMainForm nil)"
track: B
prio: 65
type: bug
blocked-by: []
status: open
owner: ""
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
