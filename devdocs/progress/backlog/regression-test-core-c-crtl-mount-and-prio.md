---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh c_mntprio26 "$(/tmp/c_mntprio26)" "$(printf '1 1 1\n2 -1 1\n3 3 0\n4 -1 1\n5 0\n6 0\n7 [/dev/sda1] `. The job's own `src` (`test/c_crtl_mount_and_prio.c`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-core#src:test/c_crtl_mount_and_prio.c at 1236bf31f930 in step 2/2, `tools/expect_same.sh c_mntprio26 "$(/tmp/c_mntprio26)" "$(printf '1 1 1\n2 -1 1\n3 3 0\n4 -1 1\n5 0\n6 0\n7 [/dev/sda1]…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T23:24:59Z
- **Test source:** test/c_crtl_mount_and_prio.c tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh c_mntprio26 "$(/tmp/c_mntprio26)" "$(printf '1 1 1\n2 -1 1\n3 3 0\n4 -1 1\n5 0\n6 0\n7 [/dev/sda1] [/mnt/my disk] [ext4] 0 2\n8 0 1\n9 [/mnt/back\\\\slash] [ro] 1 0\n10 1')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/c_crtl_mount_and_prio.c'` at 1236bf31f93084fe322e626880cc6132a33cf64a

## Range
> **The named sha `1236bf31f930` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1236bf31f930`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-3677136/c_mntprio26  [code=294680B  data=13680B  bss=74960B  procs=781]
expect_same: MISMATCH [c_mntprio26]
--- expected
+++ actual
@@ -6,5 +6,5 @@
 6 0
 7 [/dev/sda1] [/mnt/my disk] [ext4] 0 2
 8 0 1
-9 [/mnt/back\\slash] [ro] 1 0
+9 [/mnt/back\slash] [ro] 1 0
 10 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
