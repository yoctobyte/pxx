---
type: decide
track: U
prio: 8
summary: two tests in the corpus now require opposite things from `raise` — test_exception_object_leaks needs the handler to FREE the caught object, test_exception_threads_race re-raises objects it still owns and needs it NOT to; the current guard cannot satisfy both and the tier is RED on the second
tags: [exceptions, ownership, memory-leak, semantics]
---

## The fork

`620989250` made a caught exception object be freed at handler exit, fixing a
real leak (1478 of 1500 raises leaked their object, on every backend). Its
premise, stated in its own comment:

> `raise E.Create(..)` TRANSFERS the reference the constructor made; it does not
> add another. Something at handler exit has to drop it.

True for that shape. But `raise <an existing object reference>` is a different
shape: the program still holds and still owns the object, and freeing it at
handler exit is a use-after-free. **Both shapes are in the corpus today and both
are deliberate.**

    test/test_exception_object_leaks.pas   `raise EBoom.Create('boom')`
                                           -> handler MUST free, or it leaks
    test/test_exception_threads_race.pas   objects created once, re-raised in a
                                           loop -> handler MUST NOT free

The second is not incidental. Its header says why it does that: "an exception
that allocates takes the heap lock on every raise, which serialises the threads
and hides the interleaving under test." Allocating per raise would defeat the
race detector it exists to be.

No setting of the current guard satisfies both, which is why this is a decision
and not a bug fix.

## Status: the tier is RED on this

Deterministic, and it reproduces without threads at all — 15 lines, 5 iterations:

    program reraise;
    type TMyErr = class Code: Integer; end;
    var obj: TMyErr; i, caught: Integer;
    begin
      obj := TMyErr.Create; obj.Code := 7;
      caught := 0;
      for i := 1 to 5 do
      begin
        try raise obj;
        except on e: TMyErr do if e.Code = 7 then Inc(caught); end;
      end;
      WriteLn('caught=', caught, ' code=', obj.Code);
    end.

    compiler/ at 620989250^ (992aa2a20)   caught=5 code=7   exit 0
    compiler/ AT 620989250 and since      SIGSEGV           exit 139

The second raise touches freed memory. The threads test is merely where it was
noticed; threads, TLS and the shadow chain have nothing to do with it. See
backlog/regression-test-threads-test-exception-threads-race for the bisect.

## Options

**(a) Adopt Delphi/FPC ownership: `raise` always transfers, the handler always
frees.** Cheapest — the code is already this. Delphi programs are written
`raise E.Create(..)` so the shape that breaks is rare in real code. But it makes
`raise <existing object>` a use-after-free with no diagnostic, and it forces
test_exception_threads_race to allocate per raise, weakening the one test we
have for the shared-slot races (it would serialise on the heap lock, which is
what its header says it is avoiding).

**(b) Free only what the RAISE SITE constructed. RECOMMENDED.** Semantically the
honest rule: the machinery drops exactly the reference it was given. Keeps the
leak fix for the shape that was measured leaking, keeps the threads test as
written, and never frees an object the program still owns.

Cost, and it is the real argument against: ownership is decided at the raise
site and consumed at the handler, which can be in another procedure, so it must
be communicated at RUNTIME and PER THREAD — a process-wide flag would reproduce
exactly the class of race this test exists to catch. That means a new status
slot. Reads are free (`IR_EXC_STORE` routes through `IRExcStoreSlot`, which is
why slot 6 cost no backend work), but the WRITE happens in each backend's
`IR_RAISE` codegen beside the existing `BSS_EXC_CLS` store — six backends.

**(c) Reuse BSS_EXC_CLS by writing REC_NONE for non-owned raises. REJECTED, do
not take this shortcut.** It looks free and it is not: `BSS_EXC_CLS` is also
read by the `IR_EXC_MATCH` fallback that matches `on E: T` where
`IRClassMatchRuntime` is unavailable — i.e. on ESP, which has no builtin unit.
It would silently stop matching handlers for re-raised objects on that target.
I checked this before proposing it, which is the only reason it is written down
as rejected rather than attempted.

## The trade, measured rather than predicted

From Track T's `tstate/runs-seven.ndjson` (frank-coordinator). Both tests entered
the tier in the SAME run — `e7be39f9a505`, which is `620989250`'s own:

    test_exception_object_leaks   first_seen 13:33:31Z   reds:  0   never red, ever
    test_exception_threads_race   new_red    13:27:15Z   reds: 53   still_red through 18:00:08Z

So `620989250` bought a test that has never once failed, at the cost of one that
has failed in every run since. This is why "reverting swaps one red for another"
is not a guess: the archive only ever saw the leak test in its fixed state, so
reverting moves the red rather than removing it.

## Interim

Nothing is reverted, deliberately, and the tier stays RED at `test-threads`
until this is decided. Whoever takes the decision should
expect the broad tier to stay red at test-threads until it lands; the per-fix
quick tier is unaffected and green.

## Note on how this was found

`620989250` carries `session_01Hkux3cssbhbVSdw6JvJamq`, which is the session
that wrote this ticket. A trailer names a SESSION and not an agent — agents span
several across restarts (seven session ids against four known-active agents in
one 8-hour window) — so this is recorded as provenance, not as authorship, and
nobody should route this ticket on it.
