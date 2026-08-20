---
track: A
prio: 45
type: bug
blocked-by: []
summary: "SetLength shrinking a dynamic array of interfaces drops the tail elements without releasing them — shrinking 4→2 destroys 0 objects where FPC destroys 2. A leak, not a crash; the surviving elements and a later re-grow are all correct."
status: backlog
owner: unassigned
---

# SetLength shrink does not release dropped interface elements

- **Track A** (`PXXDynSetLen` in `compiler/builtin/builtinheap.pas` and the
  descriptor it walks).
- Found 2026-08-20 by an FPC differential probe of interfaces in containers.

## Measured

```pascal
var d: array of IFoo; i: Integer;
SetLength(d, 4);
for i := 0 to 3 do d[i] := TFoo.Create('s');
SetLength(d, 2);
writeln(destroyed);          { FPC: 2    pxx: 0 }
```

Everything else about the operation is right: the two survivors keep their
values, re-growing to 4 leaves `d[2]` nil, and the final tally is 2 of 4 rather
than a crash. Purely the dropped tail that leaks.

## Cause

`PXXDynSetLen` releases the dropped elements through the array's element
descriptor, which knows strings and managed records — the same `baseKind` set as
`PXXArrayReleaseImmediate` (1 = string, 3 = record + descriptor). A COM interface
element has no kind there, so the tail is simply forgotten.

## Relation to the other interface-container tickets

This is one of a family found the same day, all of them the element/member kind
being invisible to a container-level walk:

- `bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit` (static array)
- this one (dynamic array, shrink)
- `bug-a-a-record-copy-does-not-retain-an-interface-field` (record copy)
- `bug-a-class-managed-fields-not-finalized-on-destroy` (the original, and the
  one holding the deadlock blocker)

They want ONE fix, not four: an interface member kind in the descriptor plus a
release path that runs outside the non-reentrant heap spinlock. Do them together.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
