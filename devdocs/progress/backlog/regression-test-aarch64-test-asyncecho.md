---
prio: 70
---

# regression: test-aarch64#src:test/test_asyncecho.pas red at 88986014e07d (auto-filed by twatch)

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
