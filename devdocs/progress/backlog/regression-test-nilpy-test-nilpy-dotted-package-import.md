---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_dotted_package_import.npy red at 34c41bde6fd6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T19:36:23Z
- **Test source:** test/test_nilpy_dotted_package_import.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_dotted_package_import.npy'` at 34c41bde6fd66529206b2891337066a5a9fae50c

## Range
bad `34c41bde6fd6`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:53: error: C include file not found: "pdfgen.h" (searched: /tmp/testmgr-scratch-864795/../../lib/rtl/, /tmp/testmgr-scratch-864795/../lib/crtl/include/, /tmp/testmgr-scratch-864795/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
(tail)
pascal26:53: error: C include file not found: "pdfgen.h" (searched: /tmp/testmgr-scratch-864795/../../lib/rtl/, /tmp/testmgr-scratch-864795/../lib/crtl/include/, /tmp/testmgr-scratch-864795/../../lib/crtl/include/, lib/crtl/include/, <host system dirs>)
  near:  sysutils  mimic_reportlab_lib_colors  ../vendor/pdfgen/pdfgen.c >>>  type PDFTextObject 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
