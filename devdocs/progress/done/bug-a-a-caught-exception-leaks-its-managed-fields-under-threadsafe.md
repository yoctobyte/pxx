# A caught exception leaks every managed field under --threadsafe (x86-64)

- **Type:** bug (Track A — `compiler/ir.inc` exception lowering)
- **prio:** 65
- **Status:** done

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


## FIXED (frankC, 2026-09-01). The premise above was wrong; frankB found the discriminator.

**`PXX_TS_HARDLOCK` IS defined — but only from the CLI flag, never from
`{$THREADSAFE ON}`.** Measured, a probe printing its own ifdefs:

```
plain                          HARDLOCK no    PXX_THREADSAFE no
--threadsafe (CLI)             HARDLOCK YES   PXX_THREADSAFE YES
{$threadsafe on} only, no CLI  HARDLOCK no    PXX_THREADSAFE YES
```

So `lexer.inc:1199`'s "never defined on any build" is STALE — lines 1228-1239 of
the same function say the opposite and are newer, and the early exit it refers
to was inverted. Two comments in one function describing opposite worlds, and I
read the older one and built a whole diagnosis on it. Confirmed independently on
my own binary before acting.

Which means the attempted fix was RIGHT and its guard was aimed at the wrong
condition: `ir.inc` gates on `ThreadSafeMode` (a compiler flag, set by the
directive too) while `builtinheap`'s skip is gated on the DEFINE (set only by
the flag). Directive-only build: no define, so `PXXClassFinalize` ran its own
pass AND the emitted call ran — two passes, `live=-2740`. Flag build: define
present, the emitted call supplied the only pass — correct.

### The real bug underneath, fixed first
`{$threadsafe on}` and `--threadsafe` produced DIFFERENT BINARIES from one
source. The directive handler already REFUSES on i386/aarch64/arm32 with "the
softlock define is applied before lexing" — the identical reasoning applies to
`PXX_TS_HARDLOCK` on x86-64, and that arm was missing. One arm of a double case,
the sibling of `bug-p-threadsafe-directive-does-not-define-pxx-threadsafe`.

The refusal now covers every target. Blast radius measured before landing: ZERO
sources in the repo use the directive without the flag in their Makefile row.

With that, `ThreadSafeMode` implies the flag implies the define, so the
`ir.inc` guard is sound by construction rather than by coincidence.

### Result
```
                       before          after
--threadsafe (flag)    live=2745       live=3
plain (no directive)   live=3          live=3
```

`test/test_threadsafe_exception_managed_fields.pas` + Makefile rows, using
`assert_no_leak` (bound 200) rather than a cross-target differential. Positive
control observed, not asserted: the test fails on the parent binary at
live=2745, twelve times the bound.

`tools/gate.sh quick`: GREEN, FPC seed canary PASS.

**Still open, same lowering, NOT this:**
`bug-a-two-threads-raising-object-exceptions-corrupt-the-heap` — `PXXObjFree`'s
inner `PXXFree` still runs with no lock.

**Left for whoever wants it (frankB's measurement):** on a directive-only build
the `Free` desugar was double-finalizing — two passes over the same fields — and
did NOT corrupt or double-free, and neither of us found what absorbs the second
pass. That build can no longer be produced, so the question is now academic
rather than urgent, but it means something on the `Free` path is idempotent for
a reason nobody has written down.
