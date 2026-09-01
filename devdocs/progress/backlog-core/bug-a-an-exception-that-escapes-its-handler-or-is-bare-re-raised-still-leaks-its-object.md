---
type: bug
track: A
prio: 5
summary: raising a NEW exception from inside a handler still leaks the original (live=1997/1000 trips, re-measured 2026-09-01) — the bare `raise;` re-raise half of this ticket is now CLEAN (937 -> 3) and is no longer part of it
tags: [memory-leak, exceptions, raise]
blocked-by: decide-does-raise-of-an-existing-object-transfer-ownership
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
