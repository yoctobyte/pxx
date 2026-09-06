---
prio: 70
track: T
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_obj_data_import.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/c_obj_data_import.c at e7a805d13a09 in step 11/11, `if command -v gcc >/dev/null 2>&1; then \ printf '#include <stdio.h>\nint somebody_elses_global = 99;\nint read_it(void…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-04T07:21:00Z
- **Test source:** test/c_obj_data_import.c test/c_obj_data_export.c +3
- **Failing step:** line 11 of 11 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  if command -v gcc >/dev/null 2>&1; then \ printf '#include <stdio.h>\nint somebody_elses_global = 99;\nint read_it(void);\nint main(void){printf("%%d\\n", read_it());return 0;}\n' > /tmp/cods_imp_main.c; \ printf '#include <stdio.h>\nextern int shared_counter;\nint bump(void);\nint main(void){printf
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/c_obj_data_import.c'` at e7a805d13a0995bd8ec08e79e0604b32e4cc42f2

## Range
> **The named sha `e7a805d13a09` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `e7a805d13a09`, last good `01b56f5f8f0f`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
collect2: error: ld returned 1 exit status
(tail)
ok: /tmp/testmgr-scratch-2487013/cods_imp_x64.o  [code=108709B  data=1432B  bss=38160B  procs=478]
ok: /tmp/testmgr-scratch-2487013/cods_imp_386.o  [code=178091B  data=1360B  bss=38120B  procs=480]
ok: /tmp/testmgr-scratch-2487013/cods_exp_x64.o  [code=108806B  data=1432B  bss=38160B  procs=478]
ok: /tmp/testmgr-scratch-2487013/cods_exp_386.o  [code=178168B  data=1360B  bss=38120B  procs=480]
ok: /tmp/testmgr-scratch-2487013/cods_mat_x64.o  [code=108813B  data=1432B  bss=38176B  procs=478]
ok: /tmp/testmgr-scratch-2487013/cods_mat_386.o  [code=178304B  data=1360B  bss=38136B  procs=480]
ok: /tmp/testmgr-scratch-2487013/cods_only_x64.o  [code=108667B  data=1432B  bss=38164B  procs=477]
/usr/bin/ld: cannot find /tmp/testmgr-scratch-2487013/cods_imp_x64.o: No such file or directory
collect2: error: ld returned 1 exit status
test-emit-obj: data-import object FAILED to link

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## Triaged 2026-09-04 by frankb-78 (Track A) — does not reproduce, and the log tail says harness

**Not reproducible at HEAD.** Ran the job's own two emit steps and both gcc
links by hand at `7e271ff7d`:

```
--emit-obj            test/c_obj_data_import.c  -> ok, 108709B
--emit-obj --target=i386 same source            -> ok, 178091B
gcc main.c cods_imp_x64.o && ./a.out            -> 99   (rc 0)
gcc -m32 main.c cods_imp_386.o && ./a.out       -> 99   (rc 0)
```

**The failing sha does not contain the generator work landing that day.**
`git merge-base --is-ancestor a090fa76d 01b56f5f8f0f` is FALSE — the tested tree
predates it. Nothing in the range touches `compiler/**` for C or emit-obj.

**The log tail is self-contradictory in a way only the harness can explain.**
It prints `ok: /tmp/testmgr-scratch-2487013/cods_imp_x64.o [code=108709B ...]`
— the compiler wrote the object and reported the exact byte count this repro
reproduces — and then, in a later step of the SAME recipe:

```
/usr/bin/ld: cannot find /tmp/testmgr-scratch-2487013/cods_imp_x64.o: No such file or directory
```

A file the job created went missing between two steps of one recipe. That is not
a code generation defect; the object was produced and measured. **Re-laned to
T** on that evidence.

**RESIDUAL QUESTION, AND IT HAS AN OWNER.** "Not a compiler bug" is half a
finding. The open half is *why did `$(TESTTMP)` lose a file mid-job on seven* —
a scratch dir cleaned by a concurrent job, a tmpfs eviction, or a
`testmgr` teardown racing its own recipe. Track T owns the scratch lifecycle and
is the only lane that can see the run. **This is a signal about the harness, not
noise: whatever removed that object could remove any other, and every job that
loses one reports as a red in the subject it was testing.** Worth checking
whether the other reds in the same run share the shape.

Not claimed: that the harness is broken. Claimed: it does not reproduce, the
compiler wrote the object, and the cause is above the compiler.

## Log
- 2026-09-04 — the seven watcher saw `test-emit-obj#src:test/c_obj_data_import.c` GREEN at cf9b14600039 (tier full) and did NOT close this: this is a repeat stub (`regression-test-emit-obj-c-obj-data-import-2`, not `regression-test-emit-obj-c-obj-data-import`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-06 — the seven watcher saw `test-emit-obj#src:test/c_obj_data_import.c` GREEN at 1d9d36ff36bb (tier full) and did NOT close this: this is a repeat stub (`regression-test-emit-obj-c-obj-data-import-2`, not `regression-test-emit-obj-c-obj-data-import`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
