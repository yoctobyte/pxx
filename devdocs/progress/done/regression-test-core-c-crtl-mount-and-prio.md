---
prio: 70
track: T
summary: "RESOLVED — the EXPECTATION was wrong, not the compiler. Row 9's `/mnt/back\\slash` needed one backslash and the Makefile's printf produced two, so this job failed on its first-ever run against a string nobody had executed. Decided by the gcc oracle, not by counting escapes: gcc's own binary from the same source prints one backslash, and pxx's output is identical to gcc's on all ten rows. The T fallback lane happened to be right here — the defect really is in the recipe."
status: done
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

## RESOLVED (frankZ, plexus, 2026-09-02) — the expectation was wrong

`first-ever red` is the tell, and the ticket says so itself: no earlier passing
sha, so no interval contains a cause and every commit a range could name is
equally innocent. **A red here is a finding about the job.** It was.

```
-9 [/mnt/back\\slash] [ro] 1 0        <- expected
+9 [/mnt/back\slash] [ro] 1 0          <- actual
```

The C source writes `me.mnt_dir = (char *)"/mnt/back\\slash"`, which in C is
**one** backslash, and rows 5-7 exist to prove the `addmntent`/`getmntent_r`
escape round trip gives it back unchanged. The Makefile expectation spelled four
backslashes, which reach `printf` as `\\` and print **two**.

## Decided by an oracle, not by counting escapes

Comment-versus-code says one side is wrong and you do not know which, so I did
not reason about the quoting chain — I asked something that fails differently:

```
$ gcc -o /tmp/mnt_gcc test/c_crtl_mount_and_prio.c && /tmp/mnt_gcc | sed -n 9p
9 [/mnt/back\slash] [ro] 1 0
```

**gcc's own binary prints one backslash.** And pxx's output is `IDENTICAL` to
gcc's on all ten rows, diffed whole rather than at row 9. So the compiler and
the crtl round trip were right and only the string was wrong. Fixed in the
Makefile with the reason written beside it.

Verified: `testmgr --job 'test-core#src:test/c_crtl_mount_and_prio.c'` — `1/1
pass`, GREEN, binary `7ef59bc560b4b9fc`.

## The lane fallback was right, for once

This carried `track: T` as the no-owner FALLBACK, which is usually wrong and is
why the stub tells you to re-lane. Here it happened to land correctly: the
defect is in the recipe line, which is the harness, which is T's. Worth
recording precisely because the fallback being right is the rare case — it is
still not a finding, it is a coincidence, and the next one should be re-laned
the same way.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
