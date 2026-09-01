---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 14 of 33 is `out=$(./compiler/pascal26 /tmp/cdiag_mod.c /tmp/cdiag_mod26 2>&1); \ echo "$out" | grep -q '^ in: .*lib/crtl/src/.*\.c$'`. The job's own `src` (`test/test_header_static_body.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_header_static_body.pas at f9e495823dce in step 14/33, `out=$(./compiler/pascal26 /tmp/cdiag_mod.c /tmp/cdiag_mo` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T17:49:05Z
- **Test source:** test/test_header_static_body.pas tools/expect_same.sh +2
- **Failing step:** line 14 of 33 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  out=$(./compiler/pascal26 /tmp/cdiag_mod.c /tmp/cdiag_mod26 2>&1); \ echo "$out" | grep -q '^ in: .*lib/crtl/src/.*\.c$' \ || { echo 'cdiag_module: FAIL - an error inside a pulled crtl module must name that module'; echo "$out"; exit 1; }; \ echo 'ok: cdiag_module names the crtl module'
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_header_static_body.pas'` at f9e495823dcec87ce8840b5a11d61f7c4b9ac7d9

## Range
bad `f9e495823dce`, last good `5d983997a05a`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1182204/hdrstatic_h26  [code=147224B  data=5320B  bss=43524B  procs=532]
ok: /tmp/testmgr-scratch-1182204/hdrstatic_c26  [code=147224B  data=5272B  bss=43524B  procs=534]
ok: hdrstatic_h26 has no invented libhdrstatic.so
cdiag_module: FAIL - an error inside a pulled crtl module must name that module
ok: /tmp/testmgr-scratch-1182204/cdiag_mod26  [code=122648B  data=9312B  bss=40436B  procs=458]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-core#src:test/test_header_static_body.pas` passes at 963c289544a2 (tier native); it was red at f9e495823dce. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
