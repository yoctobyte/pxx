---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_clonehidden26 "$(/tmp/test_clonehidden26)" "$(cat test/test_clone_entry_with_a_hidden_result.e`. The job's own `src` (`test/test_clone_entry_with_a_hidden_result.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_clone_entry_with_a_hidden_result`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_clone_entry_with_a_hidden_result.pas at 9c14efd7b84a in step 2/2, `tools/expect_same.sh test_clonehidden26 "$(/tmp/test_clonehidden26)" "$(cat test/test_clone_entry_with_a_hidden_result.…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-24T22:36:31Z
- **Test source:** test/test_clone_entry_with_a_hidden_result.pas tools/expect_same.sh +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh test/test_clone_entry_with_a_hidden_result.expected`.
  ```
  tools/expect_same.sh test_clonehidden26 "$(/tmp/test_clonehidden26)" "$(cat test/test_clone_entry_with_a_hidden_result.expected)"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_clone_entry_with_a_hidden_result.pas'` at 9c14efd7b84af7fba89afdf2b17c7a10893bbe5d

## Range
> **The named sha `9c14efd7b84a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9c14efd7b84a`, last good `594cb89d4916`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-2348998/test_clonehidden26  [code=29024B  data=8524B  bss=61656B  procs=637  codeseg=32368B]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_clonehidden26]
--- expected
+++ actual
@@ -1,3 +1 @@
-threads ran 4 / 4
-handles intact 4 / 4
-CLONEHIDDENRET OK
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
