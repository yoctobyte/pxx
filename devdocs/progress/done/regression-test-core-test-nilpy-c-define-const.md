---
prio: 70
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_c_define_const.npy red at 67015a8cf7d8 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-13T12:40:55Z
- **Test source:** test/test_nilpy_c_define_const.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_c_define_const.npy'` at 67015a8cf7d83b33d76eb9867abe59d78f27f6a9

## Range
bad `67015a8cf7d8`, last good `9cc1116fad6c`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:5: error: import: no unit named sqlite3 and no shim mimic_sqlite3
(tail)
pascal26:5: error: import: no unit named sqlite3 and no shim mimic_sqlite3
  near:  sqlite3 >>>    

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged 2026-08-13 — one cause, consolidated

Not a separate regression. All four red jobs (`c_define_const`, `c_pointer`,
`sqlite_crud`, `import_sqlite`) fail at the same point — the `import` of a C
header — and all trace to the single semantic commit in the range,
`3f5511820 fix(N): a Python import can no longer resolve to a C header`.

Diagnosis, repro and the design fork are in
[[bug-n-blocking-c-header-imports-broke-the-four-tests-that-depend-on-them]]
(Track N, urgent). Closed here as a duplicate of it: three stubs for one commit
is the pile the ledger exists to prevent.
- 2026-08-13 — resolved, commit PENDING-COMMIT.
