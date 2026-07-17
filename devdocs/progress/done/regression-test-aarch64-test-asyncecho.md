---
prio: 70
resolved: 4c96b227
---

# regression: test-aarch64#src:test/test_asyncecho.pas red at 88986014e07d (auto-filed by twatch)

## Resolution (2026-07-17)

**Not a code regression — a harness flake.** The RED at `88986014` (a commit touching
only `tools/pasmith.py` + fuzz `LEDGER.json`, structurally incapable of affecting an
aarch64 async test) was a transient QEMU/socket-timing flake: the test COMPILED (`ok:`
in the log tail) and failed at *run*, 0-in-range. Verified flaky — 3/3 PASS on manual
re-run at the time, GREEN again now.

Fixed at the harness level by [[bug-t-flaky-async-multithreaded-tests-false-newred]]
(`4c96b227`): `reap()` now confirm-retries a failed run-test in the
runtime-nondeterministic classes (qemu/corpus/conformance/opt) before declaring RED, and
reports `flaky` when it recovers. This transient can no longer produce a false NEW-RED.
No compiler change was needed or made.

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-17T16:11:14Z
- **Test source:** test/test_asyncecho.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_asyncecho.pas'` at 88986014e07d32db61be699184456df72ecc1a16

## Range
bad `88986014e07d`, last good `88986014e07d`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3146132/test_aarch64_asyncecho  [code=196180B  data=1528B  bss=47276B  procs=304]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-07-17 — resolved, commit 4c96b227.
