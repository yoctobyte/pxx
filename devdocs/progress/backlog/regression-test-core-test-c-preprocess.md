---
prio: 70
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_c_preprocess.pas@1 red at 34c41bde6fd6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T19:28:34Z
- **Test source:** test/test_c_preprocess.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_c_preprocess.pas@1'` at 34c41bde6fd66529206b2891337066a5a9fae50c

## Range
bad `34c41bde6fd6`, last good `a03d31c2cd3c`, 3 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: error: C include file not found: "cprep_defs.h" (searched: /tmp/testmgr-scratch-858706/../../lib/rtl/, /tmp/testmgr-scratch-858706/../lib/crtl/include/, /tmp/testmgr-scratch-858706/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
(tail)
pascal26:2: error: C include file not found: "cprep_defs.h" (searched: /tmp/testmgr-scratch-858706/../../lib/rtl/, /tmp/testmgr-scratch-858706/../lib/crtl/include/, /tmp/testmgr-scratch-858706/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
  near: program test_c_preprocess  uses cprep_lib >>>  begin writeln 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
