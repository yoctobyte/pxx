---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 29 of 52 is `for combo in "xtensa --esp-profile=bare" "xtensa --platform=esp" "riscv32 --esp-profile=bare" "riscv32 --platform=esp"; `. The job's own `src` (`test/test_set_in_64bit_element.pas`, 4 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_set_in_64bit_element.pas at d250db9d3678 in step 29/52, `for combo in "xtensa --esp-profile=bare" "xtensa --platform=esp" "riscv32 --esp-profile=bare" "riscv32 --platform=esp";…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T19:12:52Z
- **Test source:** test/test_set_in_64bit_element.pas tools/expect_same.sh +2
- **Failing step:** line 29 of 52 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  for combo in "xtensa --esp-profile=bare" "xtensa --platform=esp" "riscv32 --esp-profile=bare" "riscv32 --platform=esp"; do \ set -- $combo; a=$1; pr=$2; \ ./compiler/pascal26 --target=$a $pr --emit-obj /tmp/espnoop_empty.pas /tmp/espnoop_e.o > /tmp/espnoop_e.log 2>&1; \ ./compiler/pascal26 --target=
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_set_in_64bit_element.pas'` at d250db9d36786f9f054b54f9428a507beca815b3

## Range
> **The named sha `d250db9d3678` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `d250db9d3678`, last good `27dd469f12c0`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3604369/set_in_6426  [code=72227B  data=5464B  bss=35380B  procs=149  codeseg=73440B]
FAIL espnoop: riscv32 --platform=esp writeln CHANGED the image -- empty[code=261568B  data=4376B] hello[code=261608B  data=4416B]; the two backends must agree that it is a no-op

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
