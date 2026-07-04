# Downcast to an inherited PROPERTY reads the wrong offset (miscompile)

- **Type:** bug (compiler — codegen / field offset, Track A)
- **Status:** backlog
- **Opened:** 2026-07-04 (found writing the TComponent test)

## Symptom

Accessing an **inherited property** through a **downcast** yields garbage;
the same field read directly, or the property read via a base ref, is correct.

```pascal
type
  TP = class private FTag: Integer; public property Tag: Integer read FTag write FTag; end;
  TT = class(TP) public Val: Integer; end;
var t: TT; c: TP;
begin
  t := TT.Create; t.Tag := 99; c := t;
  writeln(c.Tag);          { 99  — base ref, property: OK }
  writeln(TT(c).FTag);     { 99  — downcast, FIELD: OK }
  writeln(TT(c).Tag);      { GARBAGE — downcast, inherited PROPERTY: WRONG }
end.
```

So the property→field lowering under a downcast computes the wrong instance
offset. Field-direct is fine, non-cast property is fine — only
`TDescendant(baseref).InheritedProperty`.

## Impact

Silent wrong values (no crash). Common FPC pattern
(`TButton(Sender).Caption` etc.). Worked around in `test/test_tcomponent.pas`
by reading the inherited property via a base-typed ref.

## Narrowed (2026-07-04)

It is NOT inherited-specific — ANY property accessed through a class typecast
`TDescendant(baseref).Prop` reads wrong, including when the backing field is in
the cast target class itself, and when the derived class is empty:

```pascal
TP = class end;
TT = class(TP) private FTag: Integer; public property Tag: Integer read FTag write FTag; end;
... c := t;  writeln(TT(c).Tag);   { WRONG }   writeln(TT(c).FTag);  { OK }
```

So the trigger is **typecast base + property** (a field-backed getter). The
field read through the same cast is correct, and the property read via a
non-cast base is correct. Static read of the parser (member-access property path,
parser.inc ~2136-2426) shows it builds the SAME `AN_FIELD(base=castNode,
name=backingField)` a direct field access builds, and IRLowerAddress resolves
`RecFieldOffset(ResolveNodeRec(castNode), fieldName)` identically — yet runtime
diverges. So the divergence is NOT visible by static reading; needs **instrumented
codegen debugging** (dump the AN_FIELD base node + the resolved offset for the
property vs field case under the cast; suspect the property path's base node or
recName differs at codegen despite looking identical, or the cast's address
lowering is re-applied differently). A dedicated debugging session.

## Direction

Instrument `IRLowerAddress`'s `AN_FIELD` case (ir.inc ~962): log `baseNode` kind,
`ResolveNodeRec(baseNode)`, `fieldName`, and the computed offset for both the
property and the field access of the same cast. Compare. Fix so the property
getter's field offset matches the direct field access.

## Acceptance

Repro above prints 99/99/99; regression `.pas`; self-host byte-identical.
