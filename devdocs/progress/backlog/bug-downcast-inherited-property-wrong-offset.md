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

## Direction

The property-access lowering must resolve the backing field's offset from the
property's DECLARING class, independent of the static cast type — likely the
cast is re-resolving the field on the descendant and mis-locating it. Compare
the field-access path (correct) with the property-getter path under a cast.

## Acceptance

Repro above prints 99/99/99; regression `.pas`; self-host byte-identical.
