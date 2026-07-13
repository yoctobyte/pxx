---
prio: 70
---

# regression: test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh red at 8766dccbd2dd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T17:05:25Z
- **Test source:** tools/run_sqlite_thread_test.sh

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh'` at 8766dccbd2ddf9495353735c5798ffaf325d9be1

## Range
bad `8766dccbd2dd`, last good `8766dccbd2dd`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test-sqlite-threads: building threadsafe sqlite (aarch64) ...
ok: /tmp/testmgr-scratch-1801855/cstt_aarch64.oubs5Z/csqlite_thread_test26_aarch64  [code=6557740B  data=41792B  bss=51052B  procs=4158]
test-sqlite-threads: FAIL aarch64 (output mismatch)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
