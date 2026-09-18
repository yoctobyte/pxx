---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 18 is `tools/expect_same.sh test_interface_containers26 "$(/tmp/test_interface_containers26)" "$(printf 'strarr: ok\nstatic: 3\`. The job's own `src` (`test/test_interface_containers.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_interface_containers`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_interface_containers.pas@1 at 4fbed6c4157e in step 2/18, `tools/expect_same.sh test_interface_containers26 "$(/tmp/test_interface_containers26)" "$(printf 'strarr: ok\nstatic: 3…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T10:37:47Z
- **Test source:** test/test_interface_containers.pas tools/expect_same.sh
- **Failing step:** line 2 of 18 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_interface_containers26 "$(/tmp/test_interface_containers26)" "$(printf 'strarr: ok\nstatic: 3\ndyn: 2\nafter shrink: 2\nshrink: 4\nafter whole-copy nil-a: 0\nb still alive: pq\ncopy: 2\nrstatic: 3\nrdyn: 3\nrec after shrink: 2\nrshrink: 4\nrec after copy nil-a: 0\nrec b ali
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_interface_containers.pas@1'` at 4fbed6c4157ef53972bae9ffb923ecf029f50725

## Range
> **The named sha `4fbed6c4157e` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `4fbed6c4157e`, last good `7f86a12a6628`, 4 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3211401/test_interface_containers26  [code=79068B  data=6688B  bss=46604B  procs=160  codeseg=81632B]
expect_same: MISMATCH [test_interface_containers26]
--- expected
+++ actual
@@ -7,9 +7,9 @@
 b still alive: pq
 copy:    2
 rstatic: 3
-rdyn:    3
-rec after shrink: 2
-rshrink: 4
+rdyn:    0
+rec after shrink: 0
+rshrink: 0
 rec after copy nil-a: 0
 rec b alive: cc
 rcopy:   2

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
