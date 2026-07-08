---
prio: 70
---

# regression: test-core#602 red at 4dfde8f92cb4 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-08T19:13:06Z

## Repro
`tools/testmgr.py --tier full --job 'test-core#602'` at 4dfde8f92cb45a5bd516ca85578957791f1cfb49

## Range
bad `4dfde8f92cb4`, last good `4dfde8f92cb4`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
