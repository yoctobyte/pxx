---
summary: "Threaded FPC code does not compile as-is: TThread lives in palthreadobj rather than Classes, there is no cthreads shim, WaitFor is a procedure where FPC's returns LongWord, and BeginThread/TThreadID do not exist"
type: compat
track: B
prio: 35
owner: claude-B
---

# The threading surface is not where FPC code looks for it

- **Type:** compat (RTL parity) — Track B (`lib/rtl`)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** writing the `tools/fpc_diff_probe.sh` thread cases. Every one
  needed a `{$IFDEF FPC}` split in its `uses` line before it would build on
  both sides — which is the finding.

pxx has a real, working native `TThread` (`lib/rtl/palthreadobj.pas`, futex/PAL
based, no libc). The gap is entirely in **where the names live and what they
look like**, i.e. the mission's "compile real-world code as-is" line.

## The four differences

1. **`TThread` is in `palthreadobj`, not `Classes`.** Every threaded FPC/Delphi
   program says `uses Classes`. Making `Classes` re-export `TThread` is the
   obvious fix and has a real cost to weigh: `classes` currently does not depend
   on the thread machinery, and pulling `palthreadobj` in makes every
   Classes-using program carry it. **Worth a Track U call if the size/dependency
   trade-off is not obvious** — do not just do it.
2. **No `cthreads` unit.** On Unix, FPC code must have `cthreads` first in the
   program's `uses`, so portable sources start with
   `{$IFDEF UNIX}cthreads,{$ENDIF}`. pxx has no thread manager to install, so an
   empty compat shim unit would cost nothing and let those sources through
   unedited.
3. **`WaitFor` is a `procedure`.** FPC's is `function WaitFor: LongWord`,
   returning the thread's `ReturnValue`, and `r := t.WaitFor` is the common
   idiom. Today pxx compiles that expression and yields garbage — but that is a
   separate and much worse bug, filed as
   [[bug-p-procedure-method-in-an-expression-yields-garbage]]. Fixing that one
   turns this into an honest compile error; fixing this one makes the idiom
   work.
4. **`BeginThread` / `EndThread` / `TThreadID` / `WaitForThreadTerminate` do not
   exist.** The low-level FPC thread API. `palthread` has the machinery under
   its own names.

## Already done, separately

`InterLockedIncrement` and family were missing entirely and now exist in
`lib/rtl/palatomic.pas`, verified identical to FPC across all eleven
return-value cases. They still need an explicit `uses palatomic` where FPC has
them in `system` — [[bug-a-interlocked-family-needs-a-uses-clause-unlike-fpc]].

## Coverage

Six thread cases in `tools/fpc_diff_probe.sh` (`thread-*`). The ones this
ticket blocks are tagged `[known]`; `thread-tthread-waitfor` already passes, so
the core Create/Start/WaitFor/Finished path is verified against FPC today.

## Gate

Track B: `make lib-test` / `tools/gate.sh lib`. If `Classes` gains the
re-export, re-check binary size on a Classes-only demo before and after.

## Resolution 2026-08-09 (Track B) — 3 of 4 shipped, 1 escalated

**2. `cthreads`** — `lib/rtl/cthreads.pas`, deliberately EMPTY. pxx has no thread
manager to install and no libc to install one from, so "install the C thread
manager" correctly does nothing here. Kept dependency-free on purpose: a program
that inherited `{$IFDEF UNIX}cthreads,{$ENDIF}` from a portable header must not
thereby acquire the thread runtime.

**3. `WaitFor`** — now `function WaitFor: LongWord` returning `ReturnValue`, read
AFTER the join. FPC prints 77 for the probe program; so do we. Existing
statement-form callers are unaffected: pxx allows a discarded function result,
verified before making the change.

**4. `BeginThread` family** — `BeginThread`, `EndThread`, `TThreadID`,
`WaitForThreadTerminate`, `CloseThread` in `palthreadobj` (M3, not M1: the
registry needs a mutex and palsync is built ON palthread, so putting the
FPC-surface layer here keeps the layering one-way). `PalThreadExit` added to
palthread as EndThread's primitive — SYS_exit, not exit_group. FPC ground truth
reproduced exactly: `rc=55`, `EndThread(88)` -> `rc=88` with the following line
not reached, `SizeOf(TThreadID)=8`.

*A race the test caught, worth recording:* the slot registry first keyed on the
tid the CHILD writes, so a joiner that beat the child's first instruction found
no slot and `WaitForThreadTerminate` returned 0. The quick standalone probe
passed; the fuller test failed every time. It now matches on either tid field —
`Handle.Tid` (parent-written, what a joiner can rely on) or the child-written one
(what `EndThread` needs to find itself) — which is the RACE CONTRACT in
palthread.pas applied to a second reader. 500-iteration stress: 0 bad.

**1. `TThread` in `Classes`** — **escalated, not done**, per this ticket's own
instruction. Measuring it first showed the cost is not the size/dependency
trade-off the ticket assumed: adding `palthreadobj` to `classes` makes EVERY
`uses classes` program fail to compile without `--threadsafe`, because the gate
fires on REACHING `__pxxclone`'s unit rather than on calling it. Filed with the
numbers as [[decide-threadsafe-gate-is-reach-based-not-use-based]].

Regression test: `test/lib_fpc_thread_surface.pas`, in `make lib-test`.


## Log
- 2026-08-09 — resolved, commit e7edfade2.
