---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 7, `/tmp/test_nilpy_qthreads26 | diff -u test/test_nilpy_a_queue_across_two_threads.expected -`, which names `test/test_nilpy_a_queue_across_two_threads.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_a_queue_across_two_threads.npy at 06b0e89ee9b0 in step 2/7, `/tmp/test_nilpy_qthreads26 | diff -u test/test_nilpy_a_queue_across_two_threads.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `883da23adb0a`).
  Untriaged.
- **Found:** 2026-09-11T11:06:54Z
- **Test source:** test/test_nilpy_a_queue_across_two_threads.npy test/test_nilpy_a_queue_across_two_threads.expected
- **Failing step:** line 2 of 7 of the job's recipe; it names `test/test_nilpy_a_queue_across_two_threads.expected`.
  ```
  /tmp/test_nilpy_qthreads26 | diff -u test/test_nilpy_a_queue_across_two_threads.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_a_queue_across_two_threads.npy'` at 06b0e89ee9b034d39ea974853fb7c8859c8b30ae

## Range
> **The named sha `06b0e89ee9b0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `06b0e89ee9b0`, last good `3662f8a8b051`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
note: queue -> mimic_queue (shim, subset)
note: threading -> mimic_threading (shim, subset)
ok: /tmp/testmgr-scratch-4105611/test_nilpy_qthreads26  [code=1482520B  data=117460B  bss=88876B  procs=2398]
Unhandled exception: Exception: queue.Queue.put() would block forever: no other thread is alive, so nothing can satisfy this wait. In CPython this call hangs rather than returning, so nothing is being refused that a working program relies on. Use put_nowait() and catch queue.Empty/queue.Full, which is what a single-threaded poll wants -- or start the thread that was meant to feed this queue.
--- test/test_nilpy_a_queue_across_two_threads.expected	2026-09-11 05:06:39.565609828 +0000
+++ -	2026-09-11 10:57:11.388074964 +0000
@@ -1,6 +0,0 @@
-drained 20 sum 190
-loader finished True
-alive False left 0
-Empty caught
-Full caught
-timed get raised Empty while a thread was alive

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-11 — auto-closed by the seven watcher: `test-nilpy#src:test/test_nilpy_a_queue_across_two_threads.npy` passes at 6cf05c871750 (tier full); it was red at 06b0e89ee9b0. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
