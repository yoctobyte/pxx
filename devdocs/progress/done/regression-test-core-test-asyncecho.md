---
prio: 70
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_asyncecho.pas red at 60502ed0c353 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T17:19:29Z
- **Test source:** test/test_asyncecho.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_asyncecho.pas'` at 60502ed0c353c52af40748d96bc4563f47007896

## Range
bad `60502ed0c353`, last good `36d1bffda39d`, 48 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:35: error: unknown type: TPalIn6Addr
(tail)
pascal26:35: error: unknown type: TPalIn6Addr
  near: function TcpConnectAddr6  const addr  >>> TPalIn6Addr  port 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved — expected fallout of `1a32de34b`, fixed in `8711ece92`

Not a defect: `1a32de34b` made a unit's imports stop leaking into its
importers, and this source named something it reached only through an import's
import. FPC rejects it too. The fix is the missing `uses` clause in the source,
which is what landed. Verified compiling at the fixing sha.
- 2026-08-15 — resolved, commit 7b77f32af.
