---
prio: 70
---

# regression: test-core#603 red at 3615126067aa (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-08T19:43:47Z

## Repro
`tools/testmgr.py --tier full --job 'test-core#603'` at 3615126067aa26b2971d0b332abcfcd83f87edbd

## Range
bad `3615126067aa`, last good `3615126067aa`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved 2026-07-08 (cfront-agent) — gtk preproc timeout, fixed
`test-core#603` is a gtk header unit that TIMEOUT'd on the C-preprocessor O(n²)
(same family as #599/#601/#602). Passes at HEAD (0.5s after the amortized-CPrepOut
fix `d531804e`). Verified `testmgr --tier full --job test-core#603 --serial`.
- 2026-07-08 — resolved, commit d531804e.
