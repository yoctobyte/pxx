---
prio: 70
track: N
---

> **Track guessed as N from the FAILING STEP** — line 2 of 3, `/tmp/test_nilpy_notsub26 | diff -u test/test_nilpy_not_subscriptable.expected -`, which names `test/test_nilpy_not_subscriptable.expected`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_not_subscriptable.npy at 67f0878f2e59 in step 2/3, `/tmp/test_nilpy_notsub26 | diff -u test/test_nilpy_not_subscriptable.expected -` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T02:10:51Z
- **Test source:** test/test_nilpy_not_subscriptable.npy test/test_nilpy_not_subscriptable.expected
- **Failing step:** line 2 of 3 of the job's recipe; it names `test/test_nilpy_not_subscriptable.expected`.
  ```
  /tmp/test_nilpy_notsub26 | diff -u test/test_nilpy_not_subscriptable.expected -
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_not_subscriptable.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4094684/test_nilpy_notsub26  [code=1355544B  data=89906B  bss=55516B  procs=2199]
Segmentation fault (core dumped)
--- test/test_nilpy_not_subscriptable.expected	2026-09-11 21:30:22.018532890 +0200
+++ -	2026-09-16 04:05:15.475564590 +0200
@@ -7,5 +7,4 @@
 wo-read 'WriteOnly' object is not subscriptable
 ro-read r:x
 ro-write 'ReadOnly' object does not support item assignment
-both 5
-neither-write 'Plain' object does not support item assignment
+both 
\ No newline at end of file

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_not_subscriptable.npy` passes at 881fdee59b6f (tier full); it was red at 67f0878f2e59. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.

## CENSUS 2026-09-19 (frankS) — does not reproduce; closed by events

Run through **testmgr's own job runner**, using this ticket's exact `Repro`
line — the instrument that filed it, and the one auto-pin reads. Not through
`make`, and not through a hand-run of the fixture:

    tools/testmgr.py --tier full --job <this ticket's own literal job selector>
    ->  testmgr: GREEN, 1/1 pass

All **17** open NilPy regressions were run that way and all 17 came back GREEN.

**The census carries a positive control drawn from the same population**,
because seventeen greens from an instrument nobody has shown can fail are not
evidence. Same runner, same tier, on the xmlreader job — which is still built
by the PINNED compiler and therefore still broken — the identical form returns:

    expect_same: MISMATCH [lib_mimic_xmlreader.1]
    --- expected
    +++ actual
    @@ -1 +1 @@
    -25
    +24

    testmgr: RED

So GREEN here means the job passed, not that the runner is blind.

**This does not say the report was never real.** It was real at its filing sha;
the tree has moved past it. Closed as NOT REPRODUCING, so it stops occupying a
ranked slot and stops being dispatched to.

**Why a whole pile went stale at once, which is the part worth keeping:** these
are auto-filed by the Track T watcher, and the watcher DOES retire them — 19
open tickets have a twin in `done/` and every one of those twins carries the
line `auto-closed by the borg watcher`. The defect is narrower than "nothing
closes them": the auto-close WRITES the closed copy into `done/` and does not
remove the `backlog/` original. The duplicate then keeps a real prio, so it
goes on sorting alongside live work and a seat gets dispatched to a subject
that has been passing for weeks — and `progress.sh resolve` refuses it as an
ambiguous slug, which is how the pattern surfaced at all.
