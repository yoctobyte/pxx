---
prio: 70
track: T
---

> **Track T by default, because this job TIMED OUT.** The source path says what a job compiles, not what went wrong, and a timeout did not fail in any of its sources — it ran out of budget. Guessing a lane from the path is the wrong turn `bug-t-a-timeout-bisects-to-an-innocent-commit` was filed to stop, so a timeout stays T's until someone shows otherwise. Re-lane it if the budget was not the problem.
>
> It was executing line 2 of 11 when the budget ran out: `tools/expect_same.sh test_nilpy_noleak "$(/tmp/test_nilpy_noleak | tail -n 1)" "PYLEAK OK"`. That is where to look; it is not an accusation against that line.

> **The SLUG names `test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy at ebe1a9b4d011 in step 2/11, `tools/expect_same.sh test_nilpy_noleak "$(/tmp/test_nilpy_noleak | tail -n 1)" "PYLEAK OK"` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-23T21:46:13Z
- **Test source:** test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy tools/expect_same.sh
- **Failing step:** line 2 of 11 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_noleak "$(/tmp/test_nilpy_noleak | tail -n 1)" "PYLEAK OK"
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/test_nilpy_format_and_set_do_not_leak_a_temporary_list_per_call.npy'` at ebe1a9b4d0110b63c3e8e4a3a0d60f5c069ab131

## Range
> **The named sha `ebe1a9b4d011` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ebe1a9b4d011`, last good `77eff6982552`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-980262/test_nilpy_noleak  [code=657646B  data=100700B  bss=72012B  procs=2247  codeseg=659168B]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
