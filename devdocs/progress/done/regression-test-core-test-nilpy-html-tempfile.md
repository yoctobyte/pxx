---
prio: 70
---

# regression: test-core#src:test/test_nilpy_html_tempfile.npy red at 106a63cabbca (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-27T17:26:04Z
- **Test source:** test/test_nilpy_html_tempfile.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_html_tempfile.npy'` at 106a63cabbcaf58c334fc365316d9f7ce4081f00

## Range
bad `106a63cabbca`, last good `00d40e712b08`, 6 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1645643/test_nilpy_htmltmp26  [code=894712B  data=25580B  bss=8420B  procs=963]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-07-28 — resolved, commit HEAD.

## Resolution

No longer reproduces. Verified 2026-07-28 at 287b1b34d: output byte-identical
to CPython, the watcher's own job
(`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_html_tempfile.npy'`)
GREEN, and `tstate/borg.json` already records the job as `pass`.
