---
prio: 70
track: P
status: done
---

> **Track guessed as P from the FAILING STEP** — line 1 of 7, `./compiler/pascal26 --threadsafe test/thread_glibc_malloc_two_threads.pas /tmp/test_tglibc226`, which names `test/thread_glibc_malloc_two_threads.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/thread_glibc_malloc_two_threads.pas@1 at b1f2b7d8812d in step 1/7, `./compiler/pascal26 --threadsafe test/thread_glibc_malloc_two_threads.pas /tmp/test_tglibc226` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `f35167cd4e55`).
  Untriaged.
- **Found:** 2026-09-28T06:12:23Z
- **Test source:** test/thread_glibc_malloc_two_threads.pas tools/expect_same.sh
- **Failing step:** line 1 of 7 of the job's recipe; it names `test/thread_glibc_malloc_two_threads.pas`.
  ```
  ./compiler/pascal26 --threadsafe test/thread_glibc_malloc_two_threads.pas /tmp/test_tglibc226
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/thread_glibc_malloc_two_threads.pas@1'` at b1f2b7d8812dce14468da84ec8e1e0e867f3c412

## Range
> **The named sha `b1f2b7d8812d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b1f2b7d8812d`, last good `9a245b91c409`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:64: error: incompatible types: @WorkerEntry uses cdecl but the procedural type uses the Pascal convention -- declare both the same way
(tail)
pascal26:64: error: incompatible types: @WorkerEntry uses cdecl but the procedural type uses the Pascal convention -- declare both the same way

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-28 — the borg watcher saw `test-threads#src:test/thread_glibc_malloc_two_threads.pas@1` GREEN at 5c047cebce14 (tier native) and did NOT close this: the job's class is `qemu`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
- 2026-09-28 — frankD re-ran the failing step with the compiler whose sha256 is `0ded1e5d04c8` (built from master after the fix; the fix is on master): the `--threadsafe` compile of `test/thread_glibc_malloc_two_threads.pas` (step 1) exits 0, and the binary prints `survived: both threads churned glibc malloc concurrently`, rc 0. The failure was a compile-time refusal or a deterministic crash, so one run settles it; closed in the coordinator's sweep of tickets fixed on 2026-09-28.
- 2026-09-28 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
