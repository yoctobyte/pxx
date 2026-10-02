---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_obj_data_dup_a.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/c_obj_data_dup_a.c at 7b781ce15084 in step 25/261, `for t in "" "--target=i386" "--target=riscv32 --platform=esp" "--target=xtensa --platform=esp"; do \ ./compiler/pascal2…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-25T00:22:02Z
- **Test source:** test/c_obj_data_dup_a.c test/c_obj_data_dup_b.c +17
- **Failing step:** line 25 of 261 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  for t in "" "--target=i386" "--target=riscv32 --platform=esp" "--target=xtensa --platform=esp"; do \ ./compiler/pascal26 --emit-obj $t /tmp/fnp_forms.c /tmp/fnp_forms.o >/dev/null || { echo "test-emit-obj: the fn-pointer census fixture FAILED to build for [$t]"; exit 1; }; \ n=$(readelf -sW /tmp/fnp
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/c_obj_data_dup_a.c'` at 7b781ce150841c4c44a5bbc92a3983a28386db86

## Range
bad `7b781ce15084`, last good `aef4ee1310f9`, 33 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2812258/cods_dup_a.o  [code=18853B  data=1432B  bss=34640B  procs=514  codeseg=18853B]
ok: /tmp/testmgr-scratch-2812258/cods_dup_b.o  [code=18853B  data=1432B  bss=34640B  procs=514  codeseg=18853B]
test-emit-obj: duplicate definition is rejected, as gcc rejects it
test-emit-obj: the fn-pointer census fixture FAILED to build for [--target=i386]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-25 — the borg watcher saw `test-emit-obj#src:test/c_obj_data_dup_a.c` GREEN at dcb660109dad (tier full) and did NOT close this: this is a repeat stub (`regression-test-emit-obj-c-obj-data-dup-a-2`, not `regression-test-emit-obj-c-obj-data-dup-a`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## 2026-10-02 (frankuser): a second flake in the same job group, test-emit-obj#03

In two consecutive full tiers on plexus (`nice -n 15`, load ~24), #03 failed
with an object it had just written already gone:

    ok: /tmp/testmgr-scratch-1289354/cods_imp_x64.o  [code=19482B ...]
    ... five more ok: lines ...
    /usr/bin/x86_64-linux-gnu-ld.bfd: cannot find /tmp/testmgr-scratch-1289354/cods_imp_x64.o
    test-emit-obj: data-import object FAILED to link

Run alone (`--job 'test-emit-obj#03'`), it is green.

Eliminated, each by measurement or search, not reasoning:
- **Another Makefile `rm`.** A glob-expanding scan of every
  `rm ... $(TESTTMP)/...` line finds exactly one that matches
  `cods_imp_x64.o`: #03's own first line (Makefile ~37801).
- **A tool or test script deleting `*.o` or the scratch dir.** No script
  under tools/ or test/ does. The test/*.sh scripts handed `$(TESTTMP)`
  delete nothing.
- **The six-hour /tmp wiper.** A fresh `--emit-obj` object has a current
  mtime.
- **A fixed intermediate path in the compiler.** There is no `'/tmp/'`
  literal and no rename in the output path. Identical sizes for #03's
  imp_x64 and #04's dup_a in the failing run are normal; those two objects
  differ but always size alike.
- **cwd-running programs** (c_ofa26, c_xi26) unlink only their own named
  files.

**FOUND, same day.** It was neither a retry nor a second run. testmgr's
split_jobs put #03's leading `rm -f $(TESTTMP)/cods_*.o` at the END of job
#02, because a job starts at a compile line and the rm is not one. #02 runs
concurrently with #03, so the rm deleted #03's fresh objects whenever the two
overlapped, which at tier load they do. The shared-filename merge did not
join them because a glob is not a filename. A scan of every target found one
more case (espx_, #04 against #06). Both rm lines are removed.
