---
slug: regression-test-threads-test-a-threadvar-is-per-thread
title: "The threadvar test's RACE CONTROL is timing-dependent, and it is the only row that failed"
track: A
prio: 45
type: bug
status: open
owner: ""
found: 2026-09-09
found-by: twatch
blocked-by: [bug-a-a-threadvar-read-in-a-child-thread-faults-once-the-programs-globals-cross-a-size-boundary]
tags: [threads, threadvar, flaky]
summary: "NOT A COMPILER REGRESSION. Diagnosed 2026-09-09 at compiler 470240dd0eb5: of the six rows, every SUBSTANTIVE one passed (kept=4/4, zeroed-on-entry=4/4, no-crosstalk=4/4, main-copy=7) and only `control-raced` read FALSE. That row asserts a race HAPPENED between four threads hammering a plain global -- whether they overlap is the scheduler's answer, not the compiler's. Reproduced on demand: `taskset -c 0` gives control-raced=FALSE in 4 of 10 runs, and the whole box gives 0 of 20; seven was running its full tier when twatch caught it. Re-laned T->A (it is the threads test, not tooling), and prio dropped 70->45 because nothing is wrong with the product. THE REPAIR IS BLOCKED, NOT UNKNOWN: retry the round until the control races, breaking early on any substantive failure so a retry can never turn a broken threadvar into a pass. Writing it needs one more loop variable in that program's var block, and ONE MORE VARIABLE IN THAT BLOCK SEGFAULTS THE CHILD THREAD -- bug-a-a-threadvar-read-in-a-child-thread-faults-once-the-programs-globals-cross-a-size-boundary, found this way and the more serious of the two. A start barrier was rejected as the alternative: spinning on a plain global is hoistable at -O2 and a hoisted spin HANGS rather than reddens, trading a flaky row for a wedged tier job. Deleting the control is also wrong -- without it, four threads that all serialised would make `no-crosstalk` pass for the wrong reason, which is the trivial pass it exists to refuse."
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 11 is `tools/expect_same.sh test_threadvar_pt26 "$(/tmp/test_threadvar_pt26)" "$(printf 'kept=4/4\nzeroed-on-entry=4/4\nno-cros`. The job's own `src` (`test/test_a_threadvar_is_per_thread.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-threads#src:test/test_a_threadvar_is_per_thread.pas at 88a84359f5a0 in step 2/11, `tools/expect_same.sh test_threadvar_pt26 "$(/tmp/test_threadvar_pt26)" "$(printf 'kept=4/4\nzeroed-on-entry=4/4\nno-cro…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T16:11:07Z
- **Test source:** test/test_a_threadvar_is_per_thread.pas tools/expect_same.sh
- **Failing step:** line 2 of 11 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_threadvar_pt26 "$(/tmp/test_threadvar_pt26)" "$(printf 'kept=4/4\nzeroed-on-entry=4/4\nno-crosstalk=4/4\ncontrol-raced=TRUE\nmain-copy=7\nTHREADVAR OK')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-threads#src:test/test_a_threadvar_is_per_thread.pas'` at 88a84359f5a090d1bab4fd6696aedbc721509ec8

## Range
> **The named sha `88a84359f5a0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `88a84359f5a0`, last good `0e3ba86d5208`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3774362/test_threadvar_pt26  [code=167704B  data=7440B  bss=55208B  procs=579]
expect_same: MISMATCH [test_threadvar_pt26]
--- expected
+++ actual
@@ -1,6 +1,6 @@
 kept=4/4
 zeroed-on-entry=4/4
 no-crosstalk=4/4
-control-raced=TRUE
+control-raced=FALSE
 main-copy=7
-THREADVAR OK
+THREADVAR FAIL

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Diagnosis, 2026-09-09 (frankS)

### The failing row is the only one that is not about the compiler

```
kept=4/4            PASS   the threadvar kept this thread's value
zeroed-on-entry=4/4 PASS   each child's copy read 0 on entry
no-crosstalk=4/4    PASS   no child ever saw another child's `mine`
control-raced=FALSE FAIL   <- the plain global did not race
main-copy=7         PASS   main's own copy survived
```

Every claim the file exists to make passed. The one that failed asserts that
`shared`, an ordinary unsynchronised global, was observed holding another
thread's value at least once — i.e. that the four threads actually overlapped.

### Reproduced deliberately, which is what makes this a diagnosis and not a guess

| condition | control-raced=TRUE |
| --- | --- |
| whole box, unmodified binary | 20 of 20 |
| `taskset -c 0` (forced serialisation) | 6 of 10 |

Same binary both rows. seven was running its full tier when twatch sampled, so
the tier's own load is a sufficient explanation and no compiler change is
needed to produce this red.

### Why the control must not simply be deleted

The file's header already argues it: if the threadvar were an ordinary global,
`no-crosstalk` and the control would BOTH fail; if the harness were inert, the
control alone would fail. Remove it and four threads that happen to serialise
make `no-crosstalk` pass for the wrong reason — a guard that cannot fail,
printing PASS.

### The repair, written and then reverted

Retry the spawn/join round up to MAXTRY times, ending the moment the control
races **and equally the moment any substantive row fails**, so a retry can never
convert a broken threadvar into a pass; only a non-racing control buys another
round. At 6 in 10 per round on one cpu, twenty rounds is not a close call.

It needs one more Integer in the program's var block, and that is what exposed
[[bug-a-a-threadvar-read-in-a-child-thread-faults-once-the-programs-globals-cross-a-size-boundary]]:
the file at HEAD segfaults in the child thread if a single unused variable is
added there. The repair was reverted rather than reshaped, because reshaping it
to dodge the crash is a compiler-appeasement workaround for a bug that would
stay hidden.

**Rejected alternative, recorded so it is not re-derived:** a start barrier
(threads spin on a `go` flag so all four are runnable together). Spinning on a
plain global is hoistable out of the loop at -O2 and this dialect has no
`volatile` to say otherwise; the failure mode of a hoisted spin is a HANG, which
trades a flaky row for a wedged tier job.
