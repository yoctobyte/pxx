---
prio: 70
track: A
---

> **Track A from the job NAME `test-xtensa`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_cross_managed_strings.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-xtensa#src:test/test_cross_managed_strings.pas at 6a38839c2f81 in step 18/32, `./compiler/pascal26 --target=xtensa --platform=posix --x` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T22:24:11Z
- **Test source:** test/test_cross_managed_strings.pas tools/run_target.sh +4
- **Failing step:** line 18 of 32 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  ./compiler/pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh /tmp/xt_backjump.pas /tmp/xt_backjump
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-xtensa#src:test/test_cross_managed_strings.pas'` at 6a38839c2f81286e8d6a5552c94ae5dd81de61b0

## Range
> **The named sha `6a38839c2f81` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `6a38839c2f81`, last good `156be41b504a`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:2: error: target xtensa: the forward call to __pxx_run_finalizers at code offset 59154 cannot reach its body at 619376 (CALL0/CALL8 reach +-512 KiB). A BACKWARD call this far is widened automatically; a forward one cannot be, because the call site was sized before the body existed. Rebuild with --xtensa-long-calls, which reserves the long form at every forward call site (bigger and slower, and the only thing that builds an image this large today)
(tail)
ok: /tmp/testmgr-scratch-1106885/xtw_mstr  [code=278380B  data=6144B  bss=42344B  procs=276]
ok: /tmp/testmgr-scratch-1106885/xtw_mstr_x64  [code=114456B  data=6168B  bss=42548B  procs=247]
ok: /tmp/testmgr-scratch-1106885/xtc_mstr  [code=311148B  data=6144B  bss=42344B  procs=276]
pascal26:2: error: target xtensa: the forward call to __pxx_run_finalizers at code offset 59154 cannot reach its body at 619376 (CALL0/CALL8 reach +-512 KiB). A BACKWARD call this far is widened automatically; a forward one cannot be, because the call site was sized before the body existed. Rebuild with --xtensa-long-calls, which reserves the long form at every forward call site (bigger and slower, and the only thing that builds an image this large today)
  in: /tmp/testmgr-scratch-1106885/compiler/builtin/softfloat.pas
  near: , r ) ; end . >>> unit softfloat ; 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
