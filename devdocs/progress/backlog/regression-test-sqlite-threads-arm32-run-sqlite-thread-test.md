---
prio: 70
---

# regression: test-sqlite-threads-arm32#src:tools/run_sqlite_thread_test.sh red at 940b261f8678 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-14T15:02:20Z
- **Test source:** tools/run_sqlite_thread_test.sh

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-arm32#src:tools/run_sqlite_thread_test.sh'` at 940b261f8678c2d8faa70035fe60e91f9f0c7a3f

## Range
bad `940b261f8678`, last good `940b261f8678`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test-sqlite-threads: building threadsafe sqlite (arm32) ...
pascal26:21777: error: target arm32: cdecl indirect call argument block exceeds 4 core registers (stack args not supported yet) ()
  near: amt  offset    >>> static  sqlite3OsWrite 
test-sqlite-threads: FAIL arm32 (build error)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
