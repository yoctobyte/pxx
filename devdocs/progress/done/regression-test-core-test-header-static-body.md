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
## VERIFIED FIXED 2026-09-01 (frankC) — no longer reproduces at HEAD

Second pass of the 12-regression sweep. This row was RED on my FIRST pass a few
minutes earlier, at `2d9878ac8`; it is GREEN at `df509ad5c`, compiler `4fa89436ffe7`
(pin-derived rebuild, `converged after 1 round(s)`). GREEN twice.

**Cause NOT bisected and not claimed.** `f5708eb77` ("a static defined in a
used header keeps its body — scoped by provenance") and its earlier revert
`ade0ce525` both touch this test's subject and are the obvious candidates, but
I did not bisect and will not cite one as the fix.

**The sweep verdict had a shelf life of about twenty minutes**, which is worth
recording on its own: three of the six rows I had just written up as "still
live" were fixed by other sessions while the sweep was running. A regression
table in a fleet this active is a measurement with a timestamp, not a standing
fact — re-run before acting on one, including one of mine.
