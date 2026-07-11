---
prio: 53  # auto
---

# feature — real-window auto-closing GUI smoke (solitaire / eliah) + xvfb in gui-test

- **Type:** feature / test-coverage
- **Track:** B
- **Status:** working
- **Owner:** opus-night
- **Opened:** 2026-06-25
- **Found-by:** Track A, validating the GUI apps headlessly under `xvfb-run`
  (no compiler change). All `--smoke` runs and `make gui-test` pass under xvfb
  (EXIT 0), but the coverage is uneven — see below.

## Context — what xvfb validation showed

Ran every GUI app under `xvfb-run` with hard `timeout` guards, using
`$(PXX_STABLE)` (no compiler rebuild):

| App | `--smoke` | real / no-arg |
|-----|-----------|---------------|
| `examples/life/life.pas` | opens a **real GTK window**, `g_timeout_add(500, AutoQuit)` → `gtk_main_quit`, ~9 generations, **EXIT 0** | `gtk_main` forever (interactive, correct) |
| `examples/solitaire_gui` | **headless** (no window, no event loop), EXIT 0 | `gtk_main` forever |
| `apps/ide/eliah/main.pas` | **headless** (no window, no event loop), EXIT 0 | `gtk_main` forever |

`make gui-test` (the `tools/gui_suite.sh` suite: 10 PCL component tests +
solitaire + eliah) is all green under xvfb.

## Gap

Only `life --smoke` actually **renders a real window under X and then closes
itself**. solitaire's and eliah's smoke modes drive their handlers headlessly —
they never enter `gtk_main`, so the real window-creation / map / event-loop /
teardown path is **not** exercised in CI. A regression that only shows once a
real window is mapped (e.g. a GTK widget realize bug, a paint handler crash on a
live surface) would pass smoke.

## Proposal

1. **Real-window auto-closing smoke variant** for solitaire and eliah — mirror
   `life`'s `AutoQuit` pattern: a `--gui-smoke` (or extend `--smoke`) that builds
   the real window, `gtk_main`s, and self-quits after a short
   `g_timeout_add(N, AutoQuit)` (e.g. 300–500 ms), printing `SMOKE OK` then exit.
   Keep the existing headless `--smoke` assertions too (fast, no display).
2. **Run the suite under a display.** Wrap the `gui-test` target (or the real-
   window cases inside `gui_suite.sh`) in `xvfb-run -a`, with a hard `timeout`
   per app as a safety net so a missing self-quit can never hang CI. Headless
   smoke needs no display; the new real-window smoke does.
3. **Add `life` to the suite.** It is the only existing real-window self-closing
   GUI run and is currently not in `gui_suite.sh`; add it as the reference case.

## Done when

- `solitaire_gui` and `eliah` have a real-window smoke that maps a window under
  xvfb and self-closes (`SMOKE OK`, EXIT 0), guarded by `timeout`.
- `make gui-test` runs the real-window cases under `xvfb-run` and stays green.
- No run can hang: every GUI invocation in the suite is `timeout`-bounded.

## Notes

- xvfb is present (`/usr/bin/xvfb-run`, `Xvfb`); GTK3 (`libgtk-3.so.0`) present.
- Pattern to copy: `examples/life/life.pas` `AutoQuit` + `g_timeout_add` +
  `--smoke` arg dispatch (`life.pas:335`, `:426`).
- Keep it Track-B: `$(PXX_STABLE)` only, never rebuild the compiler.

## Log

- 2026-07-11 (opus-night) — **DONE.**
  - solitaire_gui + eliah gain `--gui-smoke`: build the real window, register
    `g_timeout_add(400, @GuiAutoQuit, nil)` (gtk_main_quit, one-shot), run the
    REAL event loop via Application.Run, print `GUI SMOKE OK` after it returns.
    Headless `--smoke` assertions kept unchanged.
  - `tools/gui_suite.sh`: new `gui_window_smoke` helper — each real-window case
    runs `timeout 30 xvfb-run -a <bin> --gui-smoke` (SKIP with a message when
    xvfb-run is absent); `life --smoke` added as the reference real-window case
    (compiled + run under xvfb the same way).
  - `make gui-test` green: 10 PCL tests + solitaire/eliah headless + 3
    real-window cases (solitaire, life, eliah) mapping actual windows under
    xvfb, all self-closing, all timeout-bounded.
