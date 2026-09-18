---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 3 of 134 is `if readelf -d /tmp/synthclob26 2>/dev/null | grep -q 'libc\.so\.6'; then \ echo "ok: synthclob26 imports memcmp from lib`. The job's own `src` (`test/test_synth_soname_survives_redeclaration.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_synth_soname_survives_redeclaration.pas at 4fbed6c4157e in step 3/134, `if readelf -d /tmp/synthclob26 2>/dev/null | grep -q 'libc\.so\.6'; then \ echo "ok: synthclob26 imports memcmp from li…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_synth_soname_survives_redeclaration.pas lib/crtl/src/string.c +2
- **Failing step:** line 3 of 134 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  if readelf -d /tmp/synthclob26 2>/dev/null | grep -q 'libc\.so\.6'; then \ echo "ok: synthclob26 imports memcmp from libc.so.6, not from the invented libsynthclob.so"; \ else echo "FAIL: synthclob26 has no libc.so.6 DT_NEEDED. memcmp is supposed to be a dynamic import here, so this binary is not exe
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_synth_soname_survives_redeclaration.pas'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3211401/synthclob26  [code=178407B  data=7340B  bss=67884B  procs=733  codeseg=179824B]
FAIL: synthclob26 has no libc.so.6 DT_NEEDED. memcmp is supposed to be a dynamic import here, so this binary is not exercising the path — with it inert the libsynthclob.so row above cannot fail and its silence means nothing

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
