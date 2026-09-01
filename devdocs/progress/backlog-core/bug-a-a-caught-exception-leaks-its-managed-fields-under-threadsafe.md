# A caught exception leaks every managed field under --threadsafe (x86-64)

- **Type:** bug (Track A — `compiler/ir.inc` exception lowering)
- **prio:** 65
- **Status:** open

## Measured
3000 raises of a class with one `AnsiString` field, caught each time. Same
source, same allocation count, only the `--threadsafe` flag differs:

```
--threadsafe   allocs=10975  frees=8230   live=2745
plain          allocs=10975  frees=10972  live=3
```

Identical allocs, so this is the free side alone. An exception class with a
string message is the ordinary case, not a corner — this leaks on essentially
every caught exception in a threaded program.

The string must be built at RUNTIME to see it: a folded literal is a static-rc
string that is never freed either way, and the first probe measured nothing for
that reason.

## Where it comes from
`620989250`'s handler-exit free emits a call to `PXXObjFree`, which runs
`PXXClassFinalize` then `PXXFree`. The `Free` desugar does NOT rely on
`PXXClassFinalize` alone: at `ir.inc` ~11592 it emits
`PXXClassFinalizeManaged` as a SECOND call, under the codegen heap lock, via
`HeapLockedCallProcIdx1`. The exception lowering emits no such second call.

Same lowering, same commit as
`bug-a-two-threads-raising-object-exceptions-corrupt-the-heap`, but a separate
bug: that one is the free running unlocked, this one is the managed pass not
running at all.

## An attempted fix, and why it was reverted rather than landed
Emitting the same locked `PXXClassFinalizeManaged` call at the exception site
FIXED the threadsafe case exactly — `live=2745` became `live=3` — and BROKE the
other one:

```
                 before fix        after fix
--threadsafe     live=2745         live=3        <- fixed
plain            live=3            live=-2740    <- double free
```

`live` going negative is a double free: the managed pass ran twice. The probe
carries `{$THREADSAFE ON}` in its source, so `ThreadSafeMode` is true in BOTH
runs and the guard `ThreadSafeMode and (TargetArch = TARGET_X86_64)` fired in
both — while whatever makes `PXXClassFinalize` skip its own managed pass is
evidently keyed to something else, since only the flagged run needed help.

**The guard the code and comments name for that skip does not exist.**
`PXXClassFinalize` skips its managed half under `{$ifndef PXX_TS_HARDLOCK}`,
and `lexer.inc` ~1199 records that `PXX_TS_HARDLOCK` "sits below the Exit and
is therefore never defined on any build", filed as
`bug-a-x86-64-early-exit-skips-target-defines`. So that `ifndef` is always
true, the managed pass always runs inside `PXXClassFinalize` — and the comment
at `ir.inc` ~11586, which says the pass is skipped on x86-64 `--threadsafe` and
justifies the second emitted call on that basis, describes a world that does
not exist.

**Which means the `Free` desugar may be double-finalizing too**, by the same
arithmetic that made the attempted fix double-free. That is the thing to
measure first, and it is a bigger question than this ticket: a `Free` of an
instance with managed fields, under `--threadsafe`, censused. If it double-frees
it has been doing so since that call was added; if it does not, then something
else distinguishes the two configurations and the comment is merely stale.

Nothing was landed. Reverted, rebuilt, and the baseline above re-measured on
the restored tree to confirm the revert was complete.

## Do not fix this without settling the above
Both this and the double-free are downstream of one unanswered question: what
actually decides whether `PXXClassFinalize` runs its managed pass. Three
comments in two files answer it differently from the defines. Settle that
first, then both call sites follow.
