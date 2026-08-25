---
slug: bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit
title: "After Delete/Insert/Copy, the fresh-buffer temp keeps a reference until SCOPE EXIT, so `a := nil` destroys nothing"
track: A
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
