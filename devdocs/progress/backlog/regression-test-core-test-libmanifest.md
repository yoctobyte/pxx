---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 35 of 10 is `grep -q "pxxlib.cfg in the current directory and it was NOT consulted" /tmp/unitalias_norow_bare.log`. The job's own `src` (`test/test_libmanifest.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_libmanifest.pas at 69a5f3c6fb1d in step 35/10, `grep -q "pxxlib.cfg in the current directory and it was NOT consulted" /tmp/unitalias_norow_bare.log` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T07:09:28Z
- **Test source:** test/test_libmanifest.pas tools/expect_same.sh +2
- **Failing step:** line 35 of 10 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  grep -q "pxxlib.cfg in the current directory and it was NOT consulted" /tmp/unitalias_norow_bare.log
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_libmanifest.pas'` at 69a5f3c6fb1de6dc5d4f16839d3b592f4a687296

## Range
> **The named sha `69a5f3c6fb1d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `69a5f3c6fb1d`, last good `8f9f196e22cd`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
