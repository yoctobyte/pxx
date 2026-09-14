---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 6 is `tools/expect_same.sh test_nilpy_noleak "$(/tmp/test_nilpy_noleak | tail -n 1)" "PYLEAK OK"`. The job's own `src` (`test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **The NAMED SHA cannot be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged, and it was not bisected. **That is a statement about ONE commit, not about the range**: this job still reads live `lib/**`, `test/**` and the Makefile, so a commit BELOW the named sha can have caused it. Read the Range section before concluding anything — it says how many commits here the job can actually observe, and it is the section that will tell you when the answer is genuinely the box.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: lib-test#src:test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy at 5c7d6d650e5d in step 2/6, `tools/expect_same.sh test_nilpy_noleak "$(/tmp/test_nilpy_noleak | tail -n 1)" "PYLEAK OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-14T19:57:25Z
- **Test source:** test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy tools/expect_same.sh
- **Failing step:** line 2 of 6 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_noleak "$(/tmp/test_nilpy_noleak | tail -n 1)" "PYLEAK OK"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy'` at 5c7d6d650e5dfcd9056c139c1eac23ac97bf421a

## Range
> **The named sha `5c7d6d650e5d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5c7d6d650e5d`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
ok: /tmp/testmgr-scratch-17208/test_nilpy_noleak  [code=1330968B  data=86228B  bss=56540B  procs=2103]
expect_same: MISMATCH [test_nilpy_noleak]
--- expected
+++ actual
@@ -1 +1 @@
-PYLEAK OK
+PYLEAK FAIL

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
