---
prio: 70
---

# regression: test-sqlite-threads-i386#00 red at 83006e927e35 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T04:27:56Z
- **Test source:** tools/run_sqlite_thread_test.sh

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-i386#00'` at 83006e927e35b02e76728c3a292e08dbcc0b792e

## Range
bad `83006e927e35`, last good `83006e927e35`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test-sqlite-threads: building threadsafe sqlite (i386) ...
ok: /tmp/csqlite_thread_test26_i386  [code=2827480B  data=42032B  bss=41028B  procs=4151]
test-sqlite-threads: FAIL i386 (not libc-free — has DT_NEEDED)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
