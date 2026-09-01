---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh c_crtl_enosys26 "$(/tmp/c_crtl_enosys26)" "$(printf 'fork: -1 1\nvfork: -1 1\nchroot: -1 1\nsetuid:`. The job's own `src` (`test/c_crtl_enosys_stubs.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/c_crtl_enosys_stubs.c at 3f73ad2f6a08 in step 2/2, `tools/expect_same.sh c_crtl_enosys26 "$(/tmp/c_crtl_enosys26)" "$(printf 'fork: -1 1\nvfork: -1 1\nchroot: -1 1\nsetuid…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T19:54:43Z
- **Test source:** test/c_crtl_enosys_stubs.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh c_crtl_enosys26 "$(/tmp/c_crtl_enosys26)" "$(printf 'fork: -1 1\nvfork: -1 1\nchroot: -1 1\nsetuid: -1 1\nsetgid: -1 1\nseteuid: -1 1\nsetegid: -1 1')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_crtl_enosys_stubs.c'` at 3f73ad2f6a08f46d3111aafd1e5a24c2d25ce7cc

## Range
> **The named sha `3f73ad2f6a08` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `3f73ad2f6a08`, last good `9801b0bcb2c6`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2195942/c_crtl_enosys26  [code=249624B  data=12320B  bss=64920B  procs=706]
expect_same: MISMATCH [c_crtl_enosys26]
--- expected
+++ actual
@@ -1,5 +1,24 @@
-fork: -1 1
-vfork: -1 1
+fork: 2201206 0
+fork: 0 0
+vfork: 2201207 0
+vfork: 2201208 0
+chroot: -1 1
+setuid: -1 1
+setgid: -1 1
+chroot: -1 1
+seteuid: -1 1
+setuid: -1 1
+setegid: -1 1
+setgid: -1 1
+seteuid: -1 1
+setegid: -1 1
+vfork: 0 0
+chroot: -1 1
+setuid: -1 1
+setgid: -1 1
+seteuid: -1 1
+setegid: -1 1
+vfork: 0 0
 chroot: -1 1
 setuid: -1 1
 setgid: -1 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-01 — auto-closed by the seven watcher: `test-core#src:test/c_crtl_enosys_stubs.c` passes at 963c289544a2 (tier native); it was red at 3f73ad2f6a08. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
