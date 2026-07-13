---
prio: 70
---

# regression: test-aarch64#src:test/test_streaming_enumset.pas red at adaecd1206f3 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T11:18:27Z
- **Test source:** test/test_streaming_enumset.pas tools/run_target.sh

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_streaming_enumset.pas'` at adaecd1206f335077795c37d19e3fa1ef472762b

## Range
bad `adaecd1206f3`, last good `2eaced377605`, 17 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-453093/test_aarch64_streaming_enumset  [code=290708B  data=5572B  bss=9952B  procs=400]
ok: /tmp/testmgr-scratch-453093/test_aarch64_streaming_enumset_x64  [code=142569B  data=5620B  bss=9952B  procs=400]
qemu: uncaught target signal 11 (Segmentation fault) - core dumped
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
