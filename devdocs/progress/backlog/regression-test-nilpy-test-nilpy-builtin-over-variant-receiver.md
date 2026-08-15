---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy red at 4c9da77f9368 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-15T08:39:52Z
- **Test source:** test/test_nilpy_builtin_over_variant_receiver.npy test/test_nilpy_builtin_over_variant_receiver.expected +2

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy'` at 4c9da77f9368ee00abe9614ae864cee612275db6

## Range
bad `unknown`, range **unknown** (first run covering this job at this tier, so there is no earlier passing sha to bound it) — **no idle bisect will happen**; this one needs hand-triage.

## Log tail
```
ok: /tmp/testmgr-scratch-2453462/test_nilpy_bvrecv26  [code=2265031B  data=45140B  bss=9260B  procs=1638]
ok: /tmp/testmgr-scratch-2453462/test_nilpy_pkgimp26  [code=2261310B  data=45972B  bss=8756B  procs=1646]
diff: test/test_nilpy_package_imports.expected: No such file or directory

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
