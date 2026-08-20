---
track: A
prio: 45
type: bug
blocked-by: []
summary: "A local dynamic array of interfaces is not released at scope exit — a routine that fills two elements and returns destroys neither. Explicitly nilling every element before returning is a complete workaround, which is why the shape usually looks fine."
status: backlog
owner: unassigned
---

# A local dynamic array of interfaces is not released at scope exit

- **Track A** (`compiler/symtab.inc` `EmitManagedLocalCleanup` /
  `PXXDynArrayRelease`'s descriptor walk).
- Found 2026-08-20 by an FPC differential probe of interfaces in containers.

## Measured

```pascal
procedure LocalDyn;
var d: array of IFoo;
begin
  SetLength(d, 2);
  d[0] := TFoo.Create('a');
  d[1] := TFoo.Create('b');
end;                          { FPC destroys 2 here.  pxx destroys 0. }
```

Nilling both elements first destroys 2 correctly, on pinned and HEAD alike — so
the element assignment path is fine and only the scope-exit walk is missing.

## Cause

Same shape as the static-array and SetLength-shrink tickets: the dyn-array
release walks elements by a `baseKind` that knows strings (1) and records (3),
and a COM interface element has no kind there.

## Do it with the family

`bug-a-setlength-shrink-does-not-release-dropped-interface-elements`,
`bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit`,
`bug-a-a-record-copy-does-not-retain-an-interface-field` and
`bug-a-class-managed-fields-not-finalized-on-destroy` are all the same missing
descriptor kind plus the heap-lock blocker. One change closes all five.

## Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`.
