# Downcast to an inherited PROPERTY reads the wrong offset (miscompile)

- **Type:** bug (compiler — codegen / field offset, Track A)
- **Status:** done
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

## Resolution (2026-07-04)

FIXED. The instrumentation plan was not needed — the garbage value (~4.2M, address-like) pointed at offset 0 = the VMT pointer, i.e. RecFieldOffset resolving a NON-FIELD name. Root cause: TT(c).Prop parses via ParseClassRecordSelectors (not the ~2200 member-access path statically read when filing); that function checked FindUProp only to keep property names out of method lookup, then built AN_FIELD with the property name itself -> RecFieldOffset miss -> offset 0. Sibling hole: the grouped-expression selector in ParseFactor ((expr).Prop). Both now do full property resolution: field-backed = AN_FIELD renamed to the accessor field (read+write through the cast); method-backed = getter/setter AN_CALL/AN_VIRTUAL_CALL with self [,index...] [,value] (cast path incl. writes + indexed; grouped path read-only). Regression test/test_cast_property.pas (15/15: cast read/write, inherited + own field, getter/setter methods, indexed, virtual getter dispatching on dynamic type, grouped + as-cast reads) in test-core. Self-host byte-identical, make test green. test_tcomponent's base-ref workaround can revert after next re-pin.
