---
prio: 70
track: A
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_loadfile_into_element_and_field.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **The SLUG names `test_loadfile_into_element_and_field`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-aarch64#src:test/test_loadfile_into_element_and_field.pas at ff2d50a2bde9 in step 2/2, `tools/expect_same.sh aarch64/test_aarch64_lfef "$(tools/run_target.sh aarch64 /tmp/test_aarch64_lfef)" "$(printf 'plain…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-19T16:50:17Z
- **Test source:** test/test_loadfile_into_element_and_field.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh tools/run_target.sh`.
  ```
  tools/expect_same.sh aarch64/test_aarch64_lfef "$(tools/run_target.sh aarch64 /tmp/test_aarch64_lfef)" "$(printf 'plain 14\nelem 14\nfield 14\nnbrs 0 0\nagain 14')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_loadfile_into_element_and_field.pas'` at ff2d50a2bde9395c6a0c454a002e155017623632

## Range
> **The named sha `ff2d50a2bde9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ff2d50a2bde9`, last good `b4104386ae9c`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2674598/test_aarch64_lfef  [code=168748B  data=4904B  bss=34332B  procs=149  codeseg=196320B]
expect_same: MISMATCH [aarch64/test_aarch64_lfef]
--- expected
+++ actual
@@ -3,3 +3,6 @@
 field 14
 nbrs  0 0
 again 14
+pelem 14
+pdyn  14
+pfld  14

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
