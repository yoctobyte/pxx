---
track: A
prio: 65
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "A stackless generator called after ANOTHER stackless generator had been declared got its arguments seeded into the wrong instance slots: `for v in G(1, 2, 3)` yielded `1 3 0`, silently, on every target, and a string parameter crashed. GenArgSlotOff read SymGenSlot through the parameter symbol, and the later generator had reused those symbol indices."
owner: ""
---

# A stackless generator called after a later generator seeds the wrong slots

```pascal
function G(a, b, c: Integer): Integer; generator; stackless;
begin yield a; yield b; yield c; end;
function H(k: Integer): Integer; generator; stackless;
var x: Integer;
begin x := k; yield x; end;
...
for v in G(1, 2, 3) do WriteLn(v);   // 1 3 0
```

Delete H and it prints `1 2 3`. H does not have to be called.

## Mechanism

With `PXXDBG=a.slslot`, the call site shows each argument's slot being looked up
through `SymGenSlot[Procs[G].Params[k].SymIdx]`. By then G's scope had closed and
H had reused those symbol indices, so `SymGenSlot` was either -1 (the fallback
offset 40, inside the instance header) or H's own slot number.

## Fix

`AssignStacklessSlots` records each declared parameter's offset per proc in
`ProcGenArgOff`. `GenArgSlotOff` reads that record, and falls back to the symbol
only when nothing was recorded.

## Test

`test/test_stackless_generator_called_after_a_later_generator.pas`: a row in
`test-core` and rows in the three cross targets. It prints `1 3 0` with v446 on
x86-64, i386, aarch64 and arm32.
