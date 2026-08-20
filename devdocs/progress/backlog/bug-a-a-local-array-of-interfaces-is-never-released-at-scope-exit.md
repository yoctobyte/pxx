---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A local `array[0..N] of IFoo` is never released at scope exit — a routine that fills three elements and returns destroys none of them. The same two-arm gap that left the array un-zero-initialised (now fixed) also leaves it un-cleaned: SymNeedsManagedCleanup answers False for it, and EmitManagedLocalCleanup has no per-element interface walk."
status: backlog
owner: unassigned
---

# A local array of interfaces is never released at scope exit

- **Track A** (`compiler/symtab.inc` — `SymNeedsManagedCleanup`,
  `EmitManagedLocalCleanup`; `compiler/builtin/builtinheap.pas`).
- Split out of `bug-a-a-local-array-of-interfaces-is-not-zero-initialised`, which
  fixed the crashing half (the init) and left this.

## Measured

pxx at `HEAD` with the init fix in place:

```pascal
procedure P;
var i: Integer; keep: array[0..2] of IFoo;
begin
  for i := 0 to 2 do keep[i] := TFoo.Create('r' + IntToStr(i));
end;                      { FPC destroys 3 here.  pxx destroys 0. }
```

Bounded by the array length per call, but a routine called in a loop leaks
linearly. Explicitly nilling every element before returning is a full workaround,
which is why the shape often looks fine in existing tests.

## Cause

Exactly the gap the init fix documented, on the cleanup side:

- `SymNeedsManagedCleanup` keys on `SymIsComInterface`, which answers **False for
  an array** by design, and on `RecordHasManagedFields(ElemRec)`, which is False
  for an interface UCls (no managed *fields*). So the routine is not even flagged
  as needing a cleanup block.
- `EmitManagedLocalCleanup`'s static-array arm calls `PXXArrayReleaseImmediate`,
  which understands `baseKind` 1 (string) and 3 (record + descriptor) only.

## Suggested fix

1. `SymElemIsComInterface` already exists (added by the init fix) — use it in
   `SymNeedsManagedCleanup`.
2. Add a runtime helper `PXXIntfArrayRelease(arrData, len, ifaceId)` to
   builtinheap — a straight loop over `PXXIntfRelease(itemAddr, ifaceId)`, which
   is nil-safe, so a partly-filled array is fine. Register it beside
   `PXXIntfRelease` in `parser.inc`.
3. Emit it from `EmitManagedLocalCleanup`'s array arm when
   `SymElemIsComInterface`. N-D arrays are stored flat, so `ArrLen` is the count
   — same as the existing string/record arms.

Do NOT unroll N release calls instead: `ArrLen` can be large and this is a
prologue/epilogue path.

## Note on scope

While here, check the same question for a **global** array of interfaces at
program exit, and for an interface array FIELD of a record or class — the
finalizer walks fields by kind and interfaces-in-aggregates have been the
recurring gap in this family. If either is also unhandled, fold it in rather
than filing a third ticket.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Extend
`test/test_interface_local_array_zero_init.pas` with a destroyed-count check
after the owning routine returns.
