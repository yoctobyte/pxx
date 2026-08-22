---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`procedure P(var d: TD2); begin SetLength(d, 2); d[0] := nil; end;` on `TD2 = array of array of Integer` leaves Length(d) = 0 in the caller where FPC gives 2 — the SetLength took and was then undone by the `d[0] := nil` that follows it. Every backend. Found by the same differential as bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded and NOT fixed by it."
---

# `SetLength` on a 2-D dynarray `var` param is lost

- **Type:** bug (silent wrong value across a call boundary) — Track A
- **Status:** backlog
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
