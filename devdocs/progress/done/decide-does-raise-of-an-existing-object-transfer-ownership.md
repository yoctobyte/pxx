---
type: decide
track: U
prio: 8
summary: SETTLED for option (a) by the FPC oracle -- FPC frees a raised object it did not construct, so `raise` transfers ownership unconditionally and pxx's current behaviour is the language's; test_exception_threads_race is what must change, and that rewrite is blocked on bug-a-two-threads-raising-object-exceptions-corrupt-the-heap
tags: [exceptions, ownership, memory-leak, semantics]
status: done
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


---

## SETTLED: option (a). The fork fell to a MEASUREMENT, not to a preference (frankC, 2026-09-01)

Closed by the author's invitation — "the oracle beats the author" (frankB).

**What was missing was never an argument, it was the oracle.** The options
above are carefully reasoned and the recommendation is (b); neither option
asked what Pascal actually does. `tools/differential-probes.md` exists for this
and `raise <an existing object>` is exactly a question it answers.

FPC 3.2.2, the ticket's own 15-line repro, unmodified:

```
Runtime error 216
```

The same use-after-free. And the single-raise form, which isolates what the
handler did rather than what the second raise found:

```
before:        code=7
in handler:    code=7
after handler: code=0        (-252645136 = 0xF0F0F0F0 under -gh)
heaptrc: 2 memory blocks allocated, 2 freed, 0 unfreed
```

**FPC frees a raised object it did not construct.** Its rule is that `raise`
transfers ownership unconditionally, whatever the shape of the operand, and the
handler drops it. `620989250` did not invent a semantics — it adopted the
language's, and the premise quoted in "The fork" above is not shape-specific
after all.

That reverses the recommendation. Option (b) would have pxx diverge from FPC on
a program someone MEANT to write, and pay a new per-thread status slot written
in six backends for the privilege. CLAUDE.md's test is what the source MEANT
and whether real code wants the behaviour; here the language answers directly
and no real code wants the other answer.

### The stated cost of (a) is also gone, and that half is not the oracle's

Option (a)'s objection was that `test_exception_threads_race` would have to
allocate per raise, "which would serialise on the heap lock, which is what its
header says it is avoiding". That was true when written. The thread-local heap
magazine landed at `250fdc6bd`: under `--threadsafe`, small alloc/free is a
lock-free per-thread free list and never reaches the heap lock. An exception
object is well inside the size classes, and the test is built `--threadsafe`.

So the two halves came from different places and both were needed — the FPC
reading says (a) is CORRECT, the magazine says (a) is AFFORDABLE. frankB's
words, and worth keeping: a decide ticket can be blocked on a fact about the
world and a fact about the tree at the same time.

### Consequence, and it is not free

`test_exception_threads_race` must stop re-raising pre-made objects. That
rewrite is **blocked**, on a bug found while attempting it:
`bug-a-two-threads-raising-object-exceptions-corrupt-the-heap`. Two threads
each raising a freshly constructed object SIGSEGV, because `620989250` emits a
call to `PXXObjFree` and on x86-64 the heap lock is taken by CODEGEN at
`tkGetMem`/`tkFreeMem` sites, never inside the runtime helpers — so an
allocator-mutating RTL routine reached by a call runs bare. Measured: clean at
`620989250^`, SIGSEGV at HEAD, and not the magazine (`-dPXX_NO_HEAP_MAG`
crashes identically).

So the regression ticket stays red, but on a different and better-understood
cause than the one it was filed for.

### Two things the rewrite must carry when it happens (frankB)

1. **The header sentence stops being true.** With pre-made objects, `else`
   isolates one mechanism: the class index. With per-raise allocation a
   clobbered object pointer also means a wrong class, so `else` counts two
   mechanisms. Better coverage, but the comment must say "raised its own class
   and did not catch it" rather than naming the class-index race alone.
2. **Sensitivity is a number, not a pass.** The forced-process-wide control has
   to fail at the SAME N, and per-raise allocation lengthens the loop body and
   grows the denominator the race window sits in. The header already records
   that N=100 and N=10000 passed on the broken build while N=1000 failed, so
   failure rate is not monotone in N: run the control several times at the
   current N and report a hit rate, the way the original "7 of 8 runs" line
   does. Also keep any leak bound OFF the control — the `else` arm has no
   `on E:` binder, so every wrong hit leaks its object
   (`bug-a-an-exception-that-escapes-its-handler-or-is-bare-re-raised-still-leaks-its-object`,
   open), and the control would trip a leak bound for a reason that is not the
   bug under test.
