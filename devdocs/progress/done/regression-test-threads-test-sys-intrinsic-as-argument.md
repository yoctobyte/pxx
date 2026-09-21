---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 8 of 20 is `tools/expect_same.sh test_trunc26.1 "$( (trap '' XFSZ; ulimit -f 40; ./compiler/pascal26 test/hello.pas /tmp/test_trunc2`. The job's own `src` (`test/test_sys_intrinsic_as_argument.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_sys_intrinsic_as_argument`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_sys_intrinsic_as_argument.pas at 5745f9f8f1f8 in step 8/20, `tools/expect_same.sh test_trunc26.1 "$( (trap '' XFSZ; ulimit -f 40; ./compiler/pascal26 test/hello.pas /tmp/test_trunc…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-21T10:01:38Z
- **Test source:** test/test_sys_intrinsic_as_argument.pas tools/expect_same.sh +1
- **Failing step:** line 8 of 20 of the job's recipe; it names `tools/expect_same.sh test/hello.pas`.
  ```
  tools/expect_same.sh test_trunc26.1 "$( (trap '' XFSZ; ulimit -f 40; ./compiler/pascal26 test/hello.pas /tmp/test_trunc26 2>&1 >/dev/null); echo "rc=$?")" "$(printf 'pascal26: error: the output file was truncated: /tmp/test_trunc26\n a write stored fewer bytes than it was asked to; the file on disk
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_sys_intrinsic_as_argument.pas'` at 5745f9f8f1f89bad3707e6e81a9a8abc03e6dd8d

## Range
> **The named sha `5745f9f8f1f8` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5745f9f8f1f8`, last good `e986fe667bef`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
-pascal26: error: the output file was truncated: /tmp/testmgr-scratch-1778898/test_trunc26
+pascal26: error: a write to the output file stored fewer bytes than asked: /tmp/testmgr-scratch-1778898/test_trunc26
(tail)
ok: /tmp/testmgr-scratch-1778898/test_siaa26  [code=68262B  data=4680B  bss=35364B  procs=151  codeseg=69344B]
expect_same: MISMATCH [test_trunc26.1]
--- expected
+++ actual
@@ -1,4 +1,8 @@
-pascal26: error: the output file was truncated: /tmp/testmgr-scratch-1778898/test_trunc26
-  a write stored fewer bytes than it was asked to; the file on disk is incomplete.
-  usual cause: the filesystem is full (ENOSPC) or a file-size limit.
+pascal26: error: a write to the output file stored fewer bytes than asked: /tmp/testmgr-scratch-1778898/test_trunc26
+  check all four -- the first is the commonest and the last is the one that fools people:
+    df -h <dir>   free BYTES
+    df -i <dir>   free INODES -- can hit 100% while df -h reads 9%
+    ulimit -f     a file-size limit truncates at a plausible size
+    another pascal26 writing THIS SAME PATH -- two writers interleave,
+      and the file can then end up the RIGHT size, so its size proves nothing.
 rc=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-21 — auto-closed by the borg watcher: `test-threads#src:test/test_sys_intrinsic_as_argument.pas` passes at 79852e83ae96 (tier native); it was red at 5745f9f8f1f8. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
