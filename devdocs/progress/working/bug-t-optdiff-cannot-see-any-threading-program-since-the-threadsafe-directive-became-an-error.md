---
slug: bug-t-optdiff-cannot-see-any-threading-program-since-the-threadsafe-directive-became-an-error
track: T
prio: 70
type: bug
blocked-by: [bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on]
status: working
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
