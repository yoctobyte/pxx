---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 4 is `tools/expect_same.sh test_nilpy_dundergetset26 "$(/tmp/test_nilpy_dundergetset26)" "$(printf '%b' '20\n99\n[10, 99, 30]\`. The job's own `src` (`test/test_nilpy_dunder_getitem_setitem.npy`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **The SLUG names `test_nilpy_dunder_getitem_setitem`, and that is not what broke.** The slug is derived from the job's `src:` selector so that it stays stable across a renumbering — it is the dedupe key and the close key — but `src:` says what the job is ABOUT. The failing step names `expect_same`. Read the `Failing step:` bullet, not the file name in the title, before you reproduce anything: the row the slug names may be passing.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_dunder_getitem_setitem.npy at 67f0878f2e59 in step 2/4, `tools/expect_same.sh test_nilpy_dundergetset26 "$(/tmp/test_nilpy_dundergetset26)" "$(printf '%b' '20\n99\n[10, 99, 30]…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T02:10:51Z
- **Test source:** test/test_nilpy_dunder_getitem_setitem.npy tools/expect_same.sh
- **Failing step:** line 2 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_nilpy_dundergetset26 "$(/tmp/test_nilpy_dundergetset26)" "$(printf '%b' '20\n99\n[10, 99, 30]\n42\n-1\n10\ncaught: TypeError')"
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_dunder_getitem_setitem.npy'` at 67f0878f2e594f042e00005391b213922d8f1047

## Range
> **The named sha `67f0878f2e59` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `67f0878f2e59`, last good `e572bd42501e`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-4094684/test_nilpy_dundergetset26  [code=1351448B  data=88202B  bss=54772B  procs=2197]
Segmentation fault (core dumped)
expect_same: MISMATCH [test_nilpy_dundergetset26]
--- expected
+++ actual
@@ -1,7 +1 @@
-20
-99
-[10, 99, 30]
-42
--1
-10
-caught: TypeError
+

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-16 — auto-closed by the borg watcher: `test-nilpy#src:test/test_nilpy_dunder_getitem_setitem.npy` passes at 881fdee59b6f (tier full); it was red at 67f0878f2e59. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.

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
