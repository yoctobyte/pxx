program test_cross_typeinfo_dataref;

{ IR_CONST_DATA (`IR op 68`) -- the generic data-reference constant. wasm32 had
  no arm for it and refused any body containing one, which is what `TypeInfo`
  cost on that target: the whole enclosing routine came out as `unreachable`.

  TWO SENTINEL FAMILIES ARE EXERCISED HERE ON PURPOSE, because they resolve
  through different tables and a fix for one says nothing about the other:

    * TypeInfo(TEnum) yields the ENUM's RTTI blob (ENUM_RTTI_DATAREF_BASE,
      resolved against EnumTypeRTTIOff) and is read by GetEnumName. It is NOT a
      PTypeInfo header -- reading it as one segfaults, which is how this test's
      first draft failed on x86-64 before it ever reached a cross target.
    * TypeInfo(Integer) / TypeInfo(TPoint) yield a PTypeInfo HEADER
      (TYPEINFO_REQ_DATAREF_BASE, resolved against TypeInfoReqOff).

  THE ASSERTION IS THE NAME, not that the pointer is non-nil. A cell that
  resolved to the WRONG blob is still non-nil and still distinct from its
  neighbours, so `p <> nil` and `p1 <> p2` pass on a backend that mixed the two
  tables up. The names come out of the blob the cell points at, so a wrong
  resolution prints a wrong name or crashes; either way it is not this.

  AND THE HEADER NAME IS PRINTED, NEVER COMPARED IN-PROGRAM, which is not a
  style choice. `p^.NamePtr^ = 'Integer'` answers FALSE on wasm32 while
  `WriteLn(p^.NamePtr^)` prints `Integer` -- a frozen string reached through a
  POINTER IN A RECORD FIELD compares as the field's address there
  (bug-a-wasm32-a-frozen-string-through-a-pointer-in-a-record-field-compares-
  as-the-fields-address, still open). The first version of this file compared,
  and wasm32 printed `header name [Integer] wanted [Integer]` -- a test failing
  on a bug that is not the one it is about. The comparison moved OUT of the
  program and into the harness, which compares the whole output; the assertion
  is exactly as strong and it no longer depends on an operator this target
  gets wrong. The enum rows may compare in-program and do: GetEnumName returns
  an ordinary managed string and that path is correct everywhere. }

uses typinfo;

var
  p: PTypeInfo;
  ok: Boolean;

type
  TColour = (cRed, cGreen, cBlue);
  TPoint  = record x, y: Integer; end;

procedure ShowName(q: Pointer);
begin
  p := PTypeInfo(q);
  WriteLn('header ', p^.NamePtr^);
end;

function EnumName(i: Integer; const want: string): Boolean;
var got: string;
begin
  got := GetEnumName(TypeInfo(TColour), i);
  EnumName := got = want;
  if not EnumName then WriteLn('  enum ', i, ' [', got, '] wanted [', want, ']');
end;

begin
  ok := EnumName(0, 'cRed') and EnumName(1, 'cGreen') and EnumName(2, 'cBlue');
  ok := ok and (GetEnumNameCount(TypeInfo(TColour)) = 3);
  ok := ok and (GetEnumValue(TypeInfo(TColour), 'cBlue') = 2);

  if ok then WriteLn('enums OK') else WriteLn('enums FAIL');
  ShowName(TypeInfo(Integer));
  ShowName(TypeInfo(TPoint));
end.
