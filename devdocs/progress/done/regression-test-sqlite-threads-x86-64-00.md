---
prio: 70
---

# regression: test-sqlite-threads-x86_64#00 red at 83006e927e35 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-12T04:27:56Z
- **Test source:** tools/run_sqlite_thread_test.sh

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-x86_64#00'` at 83006e927e35b02e76728c3a292e08dbcc0b792e

## Range
bad `83006e927e35`, last good `83006e927e35`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test-sqlite-threads: building threadsafe sqlite (x86_64) ...
ok: /tmp/csqlite_thread_test26_x86_64  [code=3198218B  data=42176B  bss=50532B  procs=4149]
test-sqlite-threads: FAIL x86_64 (not libc-free — has DT_NEEDED)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (Track T, 2026-07-12)

**Two causes, both resolved.**

1. The original red at `83006e927e35` was the same transient window as
   regression-test-core-131: a copysign workaround left crtl calling out to libc
   math, so zlib failed to compile (`call to undeclared function: copysign`) and
   the sqlite binaries linked libc (`not libc-free — has DT_NEEDED`). Fixed by
   796f4585 (real bit-level copysign/isinf/nextafter bodies, workarounds
   reverted); tstate recorded all five jobs FIXED at `3db9cbaad744` (5064b292).

2. The *later* aarch64/arm32 flaps (RED at e15a3705/15f50987, GREEN again right
   after) were a cross-checkout race, not the compiler:
   run_sqlite_thread_test.sh built into a fixed `/tmp/csqlite_thread_test26_$ARCH`
   shared by every checkout on the box, so a concurrent run's binary could be the
   one readelf'd. Fixed in fe462098 (private mktemp -d under TESTMGR_TMP).

GREEN at HEAD per tstate (full through 3f5aa914cac5).
- 2026-07-12 — resolved, commit fe462098.
