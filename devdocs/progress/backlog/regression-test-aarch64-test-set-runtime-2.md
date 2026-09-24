---
prio: 70
track: A
---

> **Track A from the job NAME `test-aarch64`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/test_set_runtime.pas`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# first-ever red: test-aarch64#src:test/test_set_runtime.pas at f135783b52da in step 1/3, `./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 test/test_set_runtime.pas /tmp/test_aarch64_setrt` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-23T22:42:09Z
- **Test source:** test/test_set_runtime.pas tools/expect_same.sh +1
- **Failing step:** line 1 of 3 of the job's recipe; it names `test/test_set_runtime.pas`.
  ```
  ./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 test/test_set_runtime.pas /tmp/test_aarch64_setrt
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-aarch64#src:test/test_set_runtime.pas'` at f135783b52dad41ace7cc953643b61b99eb014b4

## Range
> **The named sha `f135783b52da` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `f135783b52da`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
pascal26:42: error: compiler error: PXXMemZero not found (aarch64)
(tail)
pascal26:42: error: compiler error: PXXMemZero not found (aarch64)
  near: , 3 in cand ) ; >>> end .  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-24 — the borg watcher saw `test-aarch64#src:test/test_set_runtime.pas` GREEN at 1b36bdb71957 (tier full) and did NOT close this: this is a repeat stub (`regression-test-aarch64-test-set-runtime-2`, not `regression-test-aarch64-test-set-runtime`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
