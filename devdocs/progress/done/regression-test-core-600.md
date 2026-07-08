---
prio: 70
---

# regression: test-core#600 red at e0ccfaebfe91 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-08T18:16:28Z

## Repro
`tools/testmgr.py --tier full --job 'test-core#600'` at e0ccfaebfe91a2f4a5bc36affde447ee5373e3c1

## Range
bad `e0ccfaebfe91`, last good `25c1ddedcccb`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved 2026-07-08 (cfront-agent) — green at HEAD
`test-core#600` passes at HEAD (0.5s, verified `testmgr --tier full --job
test-core#600 --serial`). A gtk-family / transient timeout in the 25c1dded..e0ccfaeb
window; borg already reported it FIXED at 523f0295, and the gtk preproc O(n²) fix
(d531804e) removes the remaining timeout risk on the gtk header units. No code
change needed here.
- 2026-07-08 — resolved, commit d531804e.
