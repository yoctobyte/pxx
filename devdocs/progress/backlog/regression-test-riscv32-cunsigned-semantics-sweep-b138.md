---
prio: 70
track: A
---

> **Track A from the job NAME `test-riscv32`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/cunsigned_semantics_sweep_b138.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-riscv32#src:test/cunsigned_semantics_sweep_b138.c@2 at c194231297b1 in step 20/33, `sz=$(sed -n 's/.*code=\([0-9]*\)B.*/\1/p' /tmp/rv32_bigbody.log); \ test -n "$sz" && test "$sz" -gt 1048576 || \ { echo…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T11:39:42Z
- **Test source:** test/cunsigned_semantics_sweep_b138.c tools/run_target.sh +2
- **Failing step:** line 20 of 33 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  sz=$(sed -n 's/.*code=\([0-9]*\)B.*/\1/p' /tmp/rv32_bigbody.log); \ test -n "$sz" && test "$sz" -gt 1048576 || \ { echo "rv32_bigbody: code=$sz does not exceed JAL's 1048576 -- this test no longer covers the wall it was written for"; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-riscv32#src:test/cunsigned_semantics_sweep_b138.c@2'` at c194231297b18bbe645fb6fe681377f32c1a3d85

## Range
> **The named sha `c194231297b1` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c194231297b1`, last good `3daf4bc16cc1`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1374177/test_rv32x_cusweep  [code=38576B  data=1408B  bss=34320B  procs=538  codeseg=40812B]
ok: /tmp/testmgr-scratch-1374177/test_rv32_bigbody  [code=931632B  data=164360B  bss=34112B  procs=186  codeseg=933740B]
rv32_bigbody: code=931632 does not exceed JAL's 1048576 -- this test no longer covers the wall it was written for

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
