---
prio: 70
---

# regression: test-core#665 red at 8d1e694a9d8d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T07:43:51Z
- **Test source:** test/test_c_gtk_window.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#665'` at 8d1e694a9d8d4d8c639603644f260dd467fe9e9f

## Range
bad `8d1e694a9d8d`, last good `2b2a0c29fdc0`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-438560/test_c_gtk_window26  [code=43578B  data=1268B  bss=8924B  procs=13619]
xvfb-run: error: Xvfb failed to start

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (Track T, 2026-07-12)

**Not a compiler regression — test-infra flake.** Log tail is
`xvfb-run: error: Xvfb failed to start`, after the test binary already built ok.
The gtk recipes (Makefile `test-core`) called bare `xvfb-run`, which pins
servernum :99. borg runs two testmgr checkouts (dev tree + watcher clone), so
whoever grabbed :99 first won and the other's gtk jobs died. testmgr's `{"xvfb"}`
exclusive resource only serializes jobs *within* one run, not across runs.

Reproduced by occupying :99 and running the old recipe (same error verbatim);
`xvfb-run -a` passes. Fixed in fe462098. All four gtk jobs green at HEAD.
- 2026-07-12 — resolved, commit fe462098.
