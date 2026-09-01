---
slug: bug-t-optdiff-cannot-see-any-threading-program-since-the-threadsafe-directive-became-an-error
track: T
prio: 70
type: bug
blocked-by: [bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on]
status: done
found: 2026-09-01
found-by: frankZ
owner: frankZ
summary: "optdiff compiles with a bare `pascal26 -ON file`, so since d402a25b2 made `{$threadsafe on}` without `--threadsafe` a hard error, EVERY threading program in the corpus BUILD-FAILs and is counted as a skip. Five red shards will turn green on the next opt run with the -O3 miscompile they were reporting still live. The fix is to pass --threadsafe when the source carries the directive; land it AFTER the DCE bug, because a correct optdiff is red until then."
---

# optdiff stopped sweeping the threading corpus, and its next green will be false

Measured 2026-09-01 by frankZ at `130b9a3e9`, binary `59699dc0833f8110`.

`tools/optdiff.sh` builds each program with a bare `$CC $O file` (plus
`CFLAGS_C` for `*.c`). It passes no `--threadsafe`. Since `d402a25b2` the
directive alone is a hard error:

```
pascal26:1: error: {$threadsafe on} must be the --threadsafe flag: the
lock-implementation defines (PXX_TS_HARDLOCK on x86-64, PXX_TS_SOFTLOCK
elsewhere) are applied before lexing, so the directive alone builds an RTL
that disagrees with the codegen
```

All seven programs optdiff had been reporting as -O3 hangs carry that
directive, and all seven now BUILD-FAIL at today's tip — checked one by one:

```
lib_criticalsection_blocking  lib_fpc_thread_surface  lib_classes_tthread
test_threadsafe_layout_rtti   test_threadsafe_heap_lock_release
test_thread_api_no_uses       test_threadsafe_io_lock_foreign
```

optdiff counts a BUILD-FAIL as a skip, never a diff. So shards 0/1/2/3/5 go
GREEN on the next `opt` run, and the threading corpus leaves the -O3
differential sweep silently. The bug they were reporting is real and still
live at HEAD — see
[[bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on]], which
reproduces it *with* `--threadsafe` passed correctly.

**A guard that cannot fail is not a guard, and it prints PASS.**

## The fix

In `cflags_for()` (or a sibling `flags_for()`), add `--threadsafe` for any
source that carries the directive. It is the same shape as the existing
`CFLAGS_C` arm and the same reason: the Makefile already builds these programs
that way, and optdiff was the one caller that did not.

**Match it CASE-INSENSITIVELY.** Ten test sources carry the directive and
**three spell it `{$THREADSAFE ON}`** (`test_threadsafe_layout_rtti`,
`test_threadsafe_heap_lock_release`, `test_threadsafe_io_lock_foreign`). A
case-sensitive grep finds seven, silently leaves those three build-failing,
and reinstates a smaller version of the exact blind spot this ticket is about.
Measured 2026-09-01: a case-sensitive sweep of my own reported 5 sources where
there are 10.

The Makefile side of the same defect is already fixed
(`test_thread_api_no_uses`, the only recipe in the whole file that compiled a
directive-carrying source without the flag — swept case-insensitively).

Also worth a positive control the pass currently lacks: assert that the count
of BUILD-FAIL skips does not GROW between runs. This defect was invisible
precisely because five reds turning into five skips reads as an improvement.

## Sequencing

Landing this before the DCE fix is correct and will show `opt` RED for a true
reason. Say so in the commit; do not land it silently.

## Fixed — 2026-09-01, frankZ, and my own diagnosis in this ticket was wrong

`baae75b6b`. Two blind spots, and the second one was not in the ticket at all.

**The predicate I proposed here does not work and I measured it failing.** This
ticket said to grep the source for `{$threadsafe`. I wrote that, ran shard 2,
and all seven of its threading build-fails still build-failed: they carry the
directive **zero** times. The refusal is raised inside `lib/rtl/palthread.pas`,
by any program that reaches `__pxxclone` — through palthread, classes, TThread
or the parallel-for lowering — not by a directive in the test. A source-text
predicate would have read as a fix and reinstated the same blind spot. The
landed version RETRIES the build with `--threadsafe` and keeps the flag if that
succeeds, which asks the only oracle that cannot go stale, and distinguishes
the eight `*_fail.pas` that must keep failing for free.

**The second hole, found on the way: optdiff's baseline was not -O0.** The
header says -O0, the temp file is named `d0`, and the comment added with the
-O1 arm says "skipped straight from the -O0 baseline to -O2" — but the code
passed no `-O` flag at all, and the default is -O2 (`compiler.pas:908`). So the
`for L in 1 2 3` loop compared **-O2 against -O2**. That arm could not report a
difference for any program in the corpus, ever. A guard that cannot fail is not
a guard, and this one printed PASS.

Positive control, stated before the change and then checked:
`test_threadsafe_refcount_lockfree` is FAILED at -O0/-O1 and OK at -O2/-O3, all
with rc=0. Before: DIFF at -O1 only. After: DIFF at -O2 and -O3 — the two arms
that could not speak. Filed as
[[bug-a-a-refcount-test-passes-at-o2-and-fails-at-o0-and-o1]].

shard 2/12, same binary throughout: pass 151 -> 156, skip 24 -> 18, diff
0 -> 1, and the one diff is real. `test_thread_writeln_interleave` went to
`optdiff.skip` — six runs of ONE -O0 binary gave five distinct outputs.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2112c18c5.

## The residual the retry does NOT cover -- found by testing my own fix, 2026-09-02

The retry fires on a BUILD FAILURE. So it reaches every program refused by
`__pxxclone`'s lowering, and **no program that needs `--threadsafe` but still
builds without it.** That is any program whose threads come from somewhere
else: a libc `pthread_create` in its own source, or a linked C library that
starts its own. Such a program compiles clean, races an allocator with no lock,
and reports a DIFF that is not about the compiler at all.

Measured, and the instance was mine: shard 9 reported
`rc 1 vs 139: test/test_heap_magazine_foreign_thread.pas` -- a wrong answer at
-O0 and a SIGSEGV above it -- on a guard test I had added that afternoon,
against a retry I had written the same afternoon. It was missing
`{$THREADSAFE ON}`.

One instance, now closed by adding the directive. No others: every other Pascal
test that calls `pthread_create` carries it.

**The fix for the class is in the TEST, not the harness**, and that is a real
limit rather than a preference: a harness cannot tell "needs the flag" from
"does not" by looking at a program that builds either way. The directive is
what turns silent misuse into a diagnostic, and a diagnostic is the only thing
a sweep can act on. Recorded in `tools/optdiff.sh` beside the retry so the next
reader of that arm meets the limit at the same time as the mechanism.
