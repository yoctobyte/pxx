---
prio: 70
track: T
---

> **Track T by default, because this job TIMED OUT.** The source path says what a job compiles, not what went wrong, and a timeout did not fail in any of its sources — it ran out of budget. Guessing a lane from the path is the wrong turn `bug-t-a-timeout-bisects-to-an-innocent-commit` was filed to stop, so a timeout stays T's until someone shows otherwise. Re-lane it if the budget was not the problem.
>
> It was executing line 3 of 3 when the budget ran out: `for m in nilread nilwrite nilproc nilmethod wildstore; do \ out=$(/tmp/test_fpc_mem_errors26 $m 2>&1); rc=$?; \ test "$r`. That is where to look; it is not an accusation against that line.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_fpc_mem_errors.pas at ab8d550f2420 in step 3/3, `for m in nilread nilwrite nilproc nilmethod wildstore; do \ out=$(/tmp/test_fpc_mem_errors26 $m 2>&1); rc=$?; \ test "$…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-21T20:31:02Z
- **Test source:** test/test_fpc_mem_errors.pas
- **Failing step:** line 3 of 3 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  for m in nilread nilwrite nilproc nilmethod wildstore; do \ out=$(/tmp/test_fpc_mem_errors26 $m 2>&1); rc=$?; \ test "$rc" = "216" || { echo "FAIL --fpc-mem-errors $m: exit $rc, want 216"; exit 1; }; \ case "$out" in *"Runtime error 216 (access violation"*) ;; \ *) echo "FAIL --fpc-mem-errors $m: [$
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_fpc_mem_errors.pas'` at ab8d550f242065c77994e9de45cdbfab61462bfd

## Range
> **The named sha `ab8d550f2420` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ab8d550f2420`, last good `4f14d6c19d0a`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-3179912/test_fpc_mem_errors26  [code=68577B  data=5520B  bss=35644B  procs=151  codeseg=69344B]
ok: /tmp/testmgr-scratch-3179912/test_fpc_mem_errors_off26  [code=68372B  data=5152B  bss=35644B  procs=151  codeseg=69344B]
Segmentation fault (core dumped)
Segmentation fault (core dumped)
Segmentation fault (core dumped)
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-21 — auto-closed by the borg watcher: `test-core#src:test/test_fpc_mem_errors.pas` passes at ed1c3dfe6a0f (tier native); it was red at ab8d550f2420. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
