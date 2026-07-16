---
prio: 70
---

# GUI/PCL apps regressed on current stable — real window never shows (crash / 20x20)

- **Track:** A (compiler/runtime) — needs triage; may involve B (lib/pcl). The
  failure is in generated-code/runtime behaviour, not the app sources.
- **Found:** 2026-07-15 (Track W, trying to screenshot demos). Confirmed a
  regression between the Jul 12 compiler and the current pinned stable.

## Symptom

GUI apps built with the **current** `stable_linux_amd64/default/pinned` do not
show a working main window; two failure modes seen:

- `examples/solitaire_gui/solitaire_gui.pas` → the process maps only a **20x20
  unmanaged helper window** (a normal GTK artifact); the real titled toplevel is
  **never created**. App stays alive, no stderr.
- `apps/ide/eliah` (main.pas) built fresh → **`Unhandled exception`** at startup,
  exit 1, no window.

## Proof it's the compiler, not the apps

The committed `apps/ide/eliah/eliah` binary (built 2026-07-12) runs fine on `:0`:
it creates **both** the 20x20 helper `[eliah]` *and* the real
`[Eliah - IDE]` toplevel at **2200x1400, painted** (grab mean ~0.98). Same
source, rebuilt with today's compiler, throws at startup. So the PCL/forms path
(or the RTL it leans on) regressed since 2026-07-12.

## Repro

```sh
PXX=stable_linux_amd64/default/pinned

# 1) solitaire: only a 20x20 helper window, no real toplevel
$PXX examples/solitaire_gui/solitaire_gui.pas /tmp/sol
DISPLAY=:0 /tmp/sol &        # inspect: xdotool search --pid <pid> → one 20x20 win
# (headless xvfb: same — only a 10x10/20x20 window ever appears)

# 2) eliah: crashes at startup with the current compiler
$PXX -Fuapps/ide/eliah -Fuapps/ide/garin apps/ide/eliah/main.pas /tmp/eliah_new
/tmp/eliah_new                # -> "Unhandled exception", exit 1

# 3) contrast: the Jul-12 binary works
DISPLAY=:0 ./apps/ide/eliah/eliah &   # real [Eliah - IDE] 2200x1400 window
```

## Why CI didn't catch it (and the real ask)

**GUI apps need to be in the test suite with a REAL-window check.** Today:

- `tools/gui_suite.sh` `--smoke` calls `H.OnPaint(...)` **directly** and asserts
  on the handlers — it never runs `Application.Run`, so a broken real-window path
  stays green.
- `--gui-smoke` *does* run the loop but self-quits after 400ms and only checks
  for a "GUI SMOKE OK" line (i.e. "didn't crash in 400ms") — it would still miss
  the "no real toplevel" mode, and doesn't assert a startup exception is absent
  under a full run.
- Tests compile to `/tmp`; **no GUI binary is committed** except the now-stale
  `eliah`, so nothing in-tree exercises the current compiler's GUI output.

Suggested gate additions:

1. A real-window test via `tools/gui_shot.sh`: build a PCL app, `Application.Run`
   under Xvfb, assert (a) **no unhandled exception**, and (b) the app's
   **titled toplevel realizes to a real size** (grab the *biggest* window by PID,
   not the name-matched one — the 20x20 helper is expected and must be ignored;
   assert e.g. w≥400 && h≥300 and a non-blank frame >tens-of-KB).
2. `git bisect` between the 2026-07-12 stable and current pinned to find the
   offending compiler commit.

## Notes for whoever picks this up

- Grabbing by window *name = binary name* only ever finds the 20x20 helper; the
  real window carries the app's `gtk_window_set_title` (e.g. "Eliah - IDE"). This
  bit the investigation and will bite the test if it name-matches.
- Confirmed on both headless Xvfb and the live `:0` session — not a display/WM
  issue.
