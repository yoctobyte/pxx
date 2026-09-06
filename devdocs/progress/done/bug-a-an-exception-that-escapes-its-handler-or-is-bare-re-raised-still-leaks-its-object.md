---
type: bug
track: A
prio: 5
summary: "FIXED 2026-09-06 -- raising a NEW exception from inside a handler leaked the original (2001 live per 1000 trips, now 3, same 3000 allocs). The handler BODY now gets its own unwind pad, AN_TRY_FINALLY's shape reused, and the free is one procedure called from both arms. The double-free this ticket warned about is avoided WITHOUT a stored ownership bit: the unwind arm re-reads BSS_EXC_OBJ and frees only when a DIFFERENT object is in flight, which separates `raise E.Create(..)` (AN_RAISE overwrote the slot) from a bare `raise;` (its codegen writes neither) exactly. The blocker had already lifted -- decide-does-raise-of-an-existing-object-transfer-ownership is done, option (a), raise transfers ownership unconditionally. Positive control RUN: the new test built by the PINNED compiler reports live=4002 against live=2 at HEAD, allocs=7707 both. NilPy is a DIFFERENT mechanism and is unchanged, measured -- see the note added to the nilpy handler-binder ticket."
tags: [memory-leak, exceptions, raise]
status: done
---

## Measured

1000 trips, `-O2 -dPXX_ALLOC_CENSUS`, on `42507851cdde`. All shapes use
`raise Exception.Create(..)`, so none of them touches the use-after-free in
`decide-does-raise-of-an-existing-object-transfer-ownership`.

    shape                                          live    allocs
    raise inside a handler (original escapes)       2001     3000   LEAK
    bare `raise;` re-raise, caught outside           937     1871   LEAK
    ---- clean, for contrast ----
    plain caught `on E: Exception do`                  3     1871
    nested try/except, inner catches                   3     1871
    try/finally with a raise, caught outside           3     1871
    bare `except` with no binder                       3     1871
    `raise 42` (integer, not an object)                1        1
    Exception.Create + Free, never raised              3     1871

The two leaking rows are ~2 blocks and ~1 block per trip respectively, against
2 allocations per raise (the object plus its message string).

## Both are acknowledged in 620989250's comments, neither is quantified there

> A `raise;` re-raise inside the handler leaves via the exception path and never
> reaches this fall-through, so the in-flight object is not freed under itself.
> An exception that ESCAPES the handler body skips it too and leaks -- same as
> NilPy has always done here.

That is accurate about the mechanism and reads as a bounded, known gap. It is
worth having the numbers beside it: these are not rare shapes. `raise` inside a
handler is the ordinary way to wrap a low-level error in a domain one, and bare
`raise;` is the ordinary way to log-and-rethrow. Both leak the object AND its
message on every pass.

## Why this is blocked rather than fixable now

The handler frees at its normal fall-through, and both of these shapes leave
through the exception path instead, so the free is skipped. Making the exit path
free it requires knowing whether the machinery still owns the in-flight object —
which is exactly the question
`decide-does-raise-of-an-existing-object-transfer-ownership` has to settle. Under
option (b) there (free only what the raise site constructed) the ownership bit
needed here is the same bit, arriving through the same per-thread slot, so the
two should be built together rather than one guessing at the other.

Do NOT fix this by freeing at the exception path without that bit: for a bare
`raise;` the object is still in flight and the OUTER handler will free it, so an
unconditional free here is a double free rather than a leak — the same
retain/release pairing failure as `9cb079528`.

## Repro

    procedure Inner(i: Integer);
    begin
      try raise Exception.Create('m-' + Chr(48 + i mod 10));
      except on e: Exception do raise Exception.Create('outer'); end;
    end;
    { caller: try Inner(i); except on e2: Exception do Take(e2.Message); end; }

and the bare form, `except raise; end;` in Inner.

## 2026-09-01 — re-measured: the re-raise half is fixed, the escape half is not

Both rows re-run on binary `18ffb4b033d1`, same 1000-trip shapes as the table
above, `Exception.Create` in every arm:

    shape                                          live    allocs
    raise inside a handler (original escapes)       1997     9755   STILL LEAKS
    bare `raise;` re-raise, caught outside             3     4809   CLEAN
    plain caught `on E: Exception do`                  3     4809   clean

So the ticket is now ONE shape, and the summary above says so. The re-raise row
also reads clean on a binary predating today's four flush-boundary fixes
(`b788c5865`-era), so **it was not fixed by them and I did not bisect which
commit closed it** — the window is everything after the binary this ticket's
original table was taken on (`42507851cdde`, a BINARY sha, which names no
commit), and `d402a25b2` is the only exception-lowering change in it. Whoever
picks this up should confirm that rather than inherit it.

Nothing here touches the remaining shape: `raise` of a NEW exception from inside
a handler still drops the original on the floor, still ~2 blocks per trip (the
object plus its message string), and is still blocked on
`decide-does-raise-of-an-existing-object-transfer-ownership`.

## 2026-09-06 — FIXED, and the blocker was already lifted

`decide-does-raise-of-an-existing-object-transfer-ownership` is in `done/`,
settled for **option (a)** by the FPC oracle: FPC frees a raised object it did
not construct, so `raise` transfers ownership **unconditionally**. This ticket's
`blocked-by` outlived it. The ownership question it was waiting on has an
answer, and the answer is that the machinery owns the in-flight object, so the
object a handler was handling has nobody else to free it once a *different*
exception is in flight.

    shape                                     before   after   allocs
    raise inside a handler (original escapes)   2001       3     3000
    bare `raise;` re-raise, caught outside         3       3     1871

Same allocation count either side, so this is the free side alone.

### The fix, and the guard that is the whole of it

The handler BODY now gets its own unwind pad — `IR_EXC_ENTER`, body,
`IR_EXC_LEAVE` on both exits, the free emitted twice, a bare re-raise on the
unwind arm. That is `AN_TRY_FINALLY`'s shape, reused rather than reinvented,
because the two are one construct: a region whose cleanup must run whichever way
control leaves it. The free itself is now one procedure, `IREmitCaughtExcFree`
(`compiler/ir.inc`), called from both arms.

**This ticket's own warning is the design.** It said: do NOT free at the
exception path without the ownership bit, because for a bare `raise;` the object
is still in flight and the OUTER handler frees it, so an unconditional free is a
double free rather than a leak. Correct — and the bit does not have to be
stored. **The unwind arm re-reads `BSS_EXC_OBJ` and frees only if it differs
from the object it is holding.** A new `raise E.Create(..)` overwrote that slot
(`AN_RAISE` writes it); a bare `raise;` left it untouched (its codegen writes
neither slot). The pointer comparison separates the two exactly, at runtime, for
one load and one branch on a path that is already unwinding.

### Verified

- `assert_no_leak.sh` — the aimed instrument, since a value assertion physically
  cannot observe this: escape 3, re-raise 3, both under bound.
- **Positive control, run and not reasoned:** the new test built by the PINNED
  (pre-fix) compiler reports `live=4002` against `live=2` at HEAD, `allocs=7707`
  on both. The row is known to be able to fail.
- `test_exception_object_leaks`, `test_cross_exception` (which raises 42, 100
  and 77 — the integer arm that a free-everything fix segfaults), and
  `test_exception_unwind_temp_leak`: all green.
- Cost: none measurable. 300000 raise/catch trips, min-of-3 interleaved against
  the pinned compiler, 0.07s both. The pad lives INSIDE the handler arm, so a
  program that never raises pays nothing at all.

### NilPy is NOT fixed by this, measured, and it is a different mechanism

Same shape as a `.py` program — 585 live blocks on 200 trips — is **byte-identical
before and after**. For a NilPy bound `except V as e:` handler `excOwnTmp` is
never allocated (the binder local's scope exit owns the release), so no pad is
emitted and nothing changed. That belongs to
`bug-nilpy-a-handler-binder-unwound-past-by-a-different-exception-still-leaks`.

**But the discriminator that ticket says the pad "cannot currently make" is the
one this fix just used.** Its table is exactly the two cases separated here:

| the handler | binder holds | releasing it is |
| --- | --- | --- |
| `raise` / `raise e` | the in-flight object | a use-after-free |
| `raise Other(..)`, or a callee raises | an object nothing else references | correct, and the drop |

`SymSkipScopeExitRelease` skips both because it is a STATIC predicate over a
symbol kind, and the distinction is dynamic. Comparing the binder's pointer
against `BSS_EXC_OBJ` in the pad answers it at runtime. Not implemented here —
this is a Pascal-side fix and the NilPy row has its own blocker
(`bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate`) —
recorded because that ticket states the distinction as unavailable and it is not.
