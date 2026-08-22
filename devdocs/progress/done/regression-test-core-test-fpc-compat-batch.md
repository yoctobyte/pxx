---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_fpc_compat_batch.pas red at 1021bbdece65 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-22T14:49:44Z
- **Test source:** test/test_fpc_compat_batch.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_fpc_compat_batch.pas'` at 1021bbdece658fd8b34c9190ee8a8ed66c703671

## Range
bad `1021bbdece65`, last good `9cebdbb1f02c`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:132: error: undefined variable (LongWord)
(tail)
pascal26:132: error: undefined variable (LongWord)
  near:  SizeOf  System  LongWord >>>   SizeOf 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-08-22 — resolved, commit PENDING-COMMIT.

Resolved by `bug-p-sizeof-of-a-qualified-builtin-type-name` — the SizeOf
name-vs-expression token scan tested tkIdent alone for the tail of a qualified
name, so `SizeOf(System.LongWord)` went down the expression path.
