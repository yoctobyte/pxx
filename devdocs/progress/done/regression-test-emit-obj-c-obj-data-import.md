---
prio: 70
track: A
---

> **Track A from the job NAME `test-emit-obj`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/c_obj_data_import.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-emit-obj#src:test/c_obj_data_import.c at 68a99471d25c in step 11/11, `if command -v gcc >/dev/null 2>&1; then \ printf '#include <stdio.h>\nint somebody_elses_global = 99;\nint read_it(void…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-02T02:52:32Z
- **Test source:** test/c_obj_data_import.c test/c_obj_data_export.c +3
- **Failing step:** line 11 of 11 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  if command -v gcc >/dev/null 2>&1; then \ printf '#include <stdio.h>\nint somebody_elses_global = 99;\nint read_it(void);\nint main(void){printf("%%d\\n", read_it());return 0;}\n' > /tmp/cods_imp_main.c; \ printf '#include <stdio.h>\nextern int shared_counter;\nint bump(void);\nint main(void){printf
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-emit-obj#src:test/c_obj_data_import.c'` at 68a99471d25c22a09818eb19493a31e4466c867a

## Range
bad `68a99471d25c`, last good `0affa5fa87f4`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
collect2: error: ld returned 1 exit status
(tail)
ok: /tmp/testmgr-scratch-1034729/cods_imp_x64.o  [code=109529B  data=1432B  bss=38160B  procs=478]
ok: /tmp/testmgr-scratch-1034729/cods_imp_386.o  [code=179318B  data=1360B  bss=38120B  procs=480]
ok: /tmp/testmgr-scratch-1034729/cods_exp_x64.o  [code=109626B  data=1432B  bss=38160B  procs=478]
ok: /tmp/testmgr-scratch-1034729/cods_exp_386.o  [code=179395B  data=1360B  bss=38120B  procs=480]
ok: /tmp/testmgr-scratch-1034729/cods_mat_x64.o  [code=109633B  data=1432B  bss=38176B  procs=478]
ok: /tmp/testmgr-scratch-1034729/cods_mat_386.o  [code=179531B  data=1360B  bss=38136B  procs=480]
ok: /tmp/testmgr-scratch-1034729/cods_only_x64.o  [code=109487B  data=1432B  bss=38164B  procs=477]
/usr/bin/ld: cannot find /tmp/testmgr-scratch-1034729/cods_imp_x64.o: No such file or directory
collect2: error: ld returned 1 exit status
test-emit-obj: data-import object FAILED to link

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — auto-closed by the seven watcher: `test-emit-obj#src:test/c_obj_data_import.c` passes at be58f71f713a (tier full); it was red at 68a99471d25c. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
