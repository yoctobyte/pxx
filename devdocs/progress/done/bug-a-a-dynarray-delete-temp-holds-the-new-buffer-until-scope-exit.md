---
slug: bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit
title: "After Delete/Insert/Copy, the fresh-buffer temp keeps a reference until SCOPE EXIT, so `a := nil` destroys nothing"
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-25
summary: "`Delete(a, 2, 2)` then `a := nil` should destroy the three survivors at the nil. pxx destroys them at procedure exit instead, because AN_DYN_DELETE's hidden fresh-buffer temp still holds a reference and is only released by the scope-exit walk. Correct refcounts, wrong destruction TIME — visible to any destructor with a side effect, and what fpc-testsuite tarray11 checks."
---

# Measured, 2026-08-25 (HEAD, self-hosted fixedpoint)

```pascal
procedure InProc;
var a: TIA;          { TIA = array of ITest, a COM interface }
    i: LongInt;
begin
  SetLength(a, 5);
  for i := 0 to 4 do a[i] := TTest.Create(i);   { destructor prints }
  WriteLn('-- delete'); Delete(a, 2, 2);
  WriteLn('-- nil');    a := nil;
  WriteLn('-- done');
end;
```

| | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `-- delete` | destroy 2, destroy 3 | destroy 2, destroy 3 |
| `-- nil` | **destroy 0, 1, 4** | — |
| `-- done` | — | — |
| proc exit | — | **destroy 0, 1, 4** |

Nothing leaks and nothing dangles; the objects are destroyed exactly once. Only
the MOMENT is wrong, and it is wrong by one scope.

# Cause

`AN_DYN_DELETE` (and its `AN_DYN_INSERT` / `AN_DYN_COPY` twins) build a fresh
dyn-array LOCAL — `dcTempSym`, flagged `SymIsHiddenArgTemp` — fill it, and yield
its handle. The parser wraps the node in `arr := <that handle>`, and the
dyn-array store RETAINS it. So the buffer is held twice: once by `arr`, once by
the temp. `arr := nil` drops one; the second lives until the scope-exit release
walk.

The temp genuinely has to be a scope-exit local rather than an inline zero — the
lowering's own comment records why (in a loop, an inline zero would leak the
previous pass's handle). So the fix is to hand the reference OFF at the
assignment rather than to add a second one: either the store does not retain a
handle that came straight from a hidden temp, or the temp is nil'd immediately
after the store. The first is a move, the second is one extra statement the
expression lowering cannot currently emit (AN_DYN_DELETE is the RHS of an
assignment the PARSER built).

# Why it is only prio 35

It is observable only through a destructor with a side effect — a log, a file
close, a lock release, a `Free` count. That is a real class of program (RAII in
Pascal is exactly this), but nothing is corrupted and nothing leaks, and the
window is one scope.

# What it blocks

`fpc-testsuite tarray11.pp` halts at code 32, its `CheckFreedArray([0, 1, 4])`
after `c := nil`. Everything before that check now passes; this is the last
thing between that test and green.

`test/test_dynarray_delete_insert_copy_of_interfaces.pas` is built around the
divergence — every case is its own procedure ending in `a := nil` with nothing
after it, so the two compilers print the same ORDER — and its header says so.
Closing this ticket should add a statement after the final nil in one case.

# Outcome

The ticket offered two routes: make the store not retain a handle that came
from a hidden temp (a move), or nil the temp right after the store. The second,
because the first is only half a fix — suppressing the retain leaves the temp
still nominally owning the buffer, so its scope-exit release would then drop the
count the destination now depends on. A move needs BOTH halves and a raw slot
zero the IR has no spelling for. Emptying the temp after the store needs
neither.

`SetLength(temp, 0)` is the release, not a raw zero, and that choice is the
whole correctness argument: `PXXDynSetLen`'s `newLen <= 0` path nils the slot
and calls `PXXDynArrayRelease`, which DECREMENTS and only walks the elements at
refcount zero (`PXXDynArrayReleaseDepth`). So it drops exactly one reference and
destroys nothing the destination still holds — and the nil'd slot makes the
scope-exit walk a no-op, which is what removes the second reference for good.

The ticket said the extra statement was "one the expression lowering cannot
currently emit", and that is right: `AN_DYN_DELETE` is the RHS of an assignment
the PARSER built, so the arm cannot see its own store. `DynResultTempSym`
carries the temp from the arm to the `AN_ASSIGN` arm that wraps it. It is
cleared on ENTRY to `AN_ASSIGN`, before that assignment lowers its own RHS, so a
dyn node lowered somewhere that is not an assignment RHS can never leave a value
a later assignment picks up and releases early.

A nested dyn expression (`a := Copy(Copy(b,0,3),0,2)`) hands off only the OUTER
temp; the inner one is overwritten before it is read and keeps its buffer until
scope exit, exactly as all three did before. Not a regression, and written down
in the code rather than left to be rediscovered.

Net less code, not more: the seven lines that emit `SetLength(temp, 0)` were
already written out three times, once per arm, and the hand-off would have been
a fourth. They are now one `IREmitDynSetLenZero`.

# Gate

- The ticket's measured table now matches fpc 3.2.2 exactly: `destroy 0, 1, 4`
  at the `-- nil`, not at procedure exit.
- **`fpc-testsuite tarray11.pp` passes**, exit 0. It previously halted at code
  32 on its `CheckFreedArray([0, 1, 4])`. That was the ticket's stated blocker.
- `test/test_dynarray_delete_insert_copy_of_interfaces.pas` now prints a line
  AFTER its final nil — the statement its old header explicitly warned not to
  add, because the divergence made it meaningless. It is the only thing in the
  file that would catch the temp taking its reference back. `.expected`
  regenerated from fpc, which it already was.
- All 28 `test_dyn*` tests GREEN. pascal-conformance 346/0/170/34 and fgl 7/7
  unchanged. Self-host byte-identical. `gate.sh quick` GREEN.
- Leak check: 2000 iterations of Delete + Copy over an `array of ITest` in a
  loop — `live = 0` at the end and maxRSS identical to the fpc build's. The
  loop was the case the arms' head comment says forced the temp design, so it
  is the one that had to be proved.

# A separate bug the leak check found

That loop originally included `Insert`, and **segfaulted on the second pass**.
It does so on `pinned` too, so it predates this change — filed as
[[bug-a-insert-into-an-array-of-interfaces-crashes-on-the-second-pass]] with the
narrowing: it needs `Insert` AND a COM-interface element type AND a second pass;
remove any one of the three and it is correct and matches fpc. `Insert` is
consequently absent from the leak check above, which is why that check covers
Delete and Copy only.


## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
