---
prio: 70
track: N
status: done
---

> **Track guessed as N from the FAILING STEP** — line 1 of 2, `./compiler/pascal26 test/test_nilpy_import_c_header_still_works.npy /tmp/test_nilpy_imphdr26`, which names `test/test_nilpy_import_c_header_still_works.npy`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_import_c_header_still_works.npy at 25b8325d4b83 in step 1/2, `./compiler/pascal26 test/test_nilpy_import_c_header_still_works.npy /tmp/test_nilpy_imphdr26` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T11:38:32Z
- **Test source:** test/test_nilpy_import_c_header_still_works.npy tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/test_nilpy_import_c_header_still_works.npy`.
  ```
  ./compiler/pascal26 test/test_nilpy_import_c_header_still_works.npy /tmp/test_nilpy_imphdr26
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_import_c_header_still_works.npy'` at 25b8325d4b832de70e4ff573533882edd95e0dca

## Range
> **The named sha `25b8325d4b83` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `25b8325d4b83`, last good `cdae8cf6580b`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:22: error: C #if: expected ':' in conditional expression
(tail)
pascal26:22: warning: #include <bits/libc-header-start.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:22: warning: #include <bits/floatn.h> resolved from the host system (/usr/include), not pxx's own headers — ABI/macro mismatches (e.g. va_list, M_SQRT2) may silently misbehave
pascal26:22: error: C #if: expected ':' in conditional expression
  near: import stdlib >>>  import stdio 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `test-nilpy#src:test/test_nilpy_import_c_header_still_works.npy` GREEN at 0da8a0ae4200 (tier full) and did NOT close this: this is a repeat stub (`regression-test-nilpy-test-nilpy-import-c-header-still-works-2`, not `regression-test-nilpy-test-nilpy-import-c-header-still-works`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

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
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
