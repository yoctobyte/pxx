---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`procedure P(var d: TD2); begin SetLength(d, 2); d[0] := nil; end;` on `TD2 = array of array of Integer` leaves Length(d) = 0 in the caller where FPC gives 2 — the SetLength took and was then undone by the `d[0] := nil` that follows it. Every backend. Found by the same differential as bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded and NOT fixed by it."
owner: frank1-A
---

# `SetLength` on a 2-D dynarray `var` param is lost

- **Type:** bug (silent wrong value across a call boundary) — Track A
- **Status:** done
- **Opened:** 2026-08-22

## Measured

```pascal
type TD2 = array of TDA;   { TDA = array of Integer }
procedure P_2d(var d: TD2); begin SetLength(d, 2); d[0] := nil; end;
...
SetLength(d2, 7); P_2d(d2);   WriteLn(Length(d2));   { FPC: 2   pxx: 0 }
```

Zero, not seven — so the caller's handle IS being written; it ends up nil. The
one-dimensional form of the same routine (`SetLength(d, 3)` on
`var d: array of Integer`) is correct, and so is `d[0] := 99`.

## First thing to check

`d[0] := nil` where `d` is a by-ref 2-D dynarray param: the row store almost
certainly resolves to the ROOT symbol's slot rather than to element 0, so
`SetLength`'s freshly published handle is overwritten with nil. That would also
explain the exact value observed (0, not 7) — the nil lands where the new handle
was, one indirection short of the row.

Do not fix this from the description: dump the IR
(`PXXDBG=a.ir:P_2d`) and confirm which address the store targets first. Every
wrong root cause in this repo's history was a plausible story nobody measured.

## Gate

Track A's, plus the `2d` row matching fpc 3.2.2 and a nested-array ARC check
(the rows the outer array drops must be released exactly once).

## Resolved 2026-08-22

**The "First thing to check" section was right, and the IR said so in eleven
lines.** `PXXDBG=a.ir:P_2d`:

```
0: lea      a=94 [sym=d]      <- SetLength's target: write mode, so &caller_slot. RIGHT.
2: setlen_dyn a=0 b=1 ival=94
4: slotaddr a=94 [sym=d]      <- the index's base: &LOCAL slot. WRONG.
5: dynunique a=4 ...
7: index    a=5 b=6
8: store_dyn a=7 b=3
```

Two nodes for the same variable in the same three-line routine, one indirection
apart. `IR_SLOTADDR` is "the address of the variable's slot", unconditionally —
that is its documented contract and every backend implements it as a plain lea,
because other consumers (the stackless save/restore) genuinely want a by-ref
param's OWN slot. But a `var` parameter's slot does not hold the handle; it
holds the ADDRESS of the caller's handle, so the address `IR_DYNUNIQUE` needs
is the slot's CONTENTS.

That is why the two halves of one statement disagreed about what `d` meant:
`SetLength(d, 2)` arrives through `IR_LEA`, whose write mode already loads the
slot, and it was correct the whole time.

### Bigger than the ticket said

The ticket measured `d[0] := nil` giving `Length` 0. The same root cause also
made

```pascal
procedure P(var d: TD2);
begin SetLength(d, 2); SetLength(d[0], 3); d[0][1] := 9; end;
```

resize the **root** to 3 and then segfault walking rows that were never rows.
Every nested index on a by-ref dynarray param aimed at the parameter's own slot;
`nil` was simply the value that made the damage legible.

### The fix

In `ir.inc`, at the one site that builds the `IR_DYNUNIQUE` base for an ident
root: keep `IR_SLOTADDR`, and for a by-ref param wrap it in `IR_LOAD_MEM`.

```pascal
slotAddrNode := IRAppend(IR_SLOTADDR, ASTIVal[baseNode], -1, -1, 0, Ord(tyPointer));
if (Syms[ASTIVal[baseNode]].Kind = skParam) and Syms[ASTIVal[baseNode]].IsRef then
  slotAddrNode := IRAppend(IR_LOAD_MEM, slotAddrNode, -1, -1, 0, Ord(tyPointer));
```

`IR_LEA` cannot serve here — its READ mode derefs once more to the data pointer,
and `IR_DYNUNIQUE` needs the slot address in read and write mode alike, which is
the entire reason `IR_SLOTADDR` exists. `IR_LOAD_MEM` of the slot address is the
same answer in both modes, on every target, **with no backend change** — which
matters, since the ticket notes the bug was on all five.

### Verification

`test/test_dynarray_var_param_nested_index.pas`, 7/7, identical under
fpc 3.2.2 and under `-dPXX_HEAP_DEBUG`: depth 2 and 3, read and write, a
`const` param read, the depth-1 control that always worked, and an
`array of array of AnsiString` row that overwrites a populated row so the old
one must be released exactly once.

### Still open, and now measured

The sibling [[bug-a-a-dynarray-var-param-written-from-a-nested-routine-is-discarded]]
is NOT fixed by this and is worse than its own ticket says: from a nested
routine, `SetLength(d, 3)` on a `var d: TDA` leaves the caller at 5 with garbage
in `d[1]`, and the 2-D form segfaults. A nested body reaches `d` through the
capture/display path rather than as an `skParam`, so neither this fix nor the
earlier `IR_STORE_SYM` one applies. Taken next.

## Log
- 2026-08-22 — resolved, commit 546278c8b.
