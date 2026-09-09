program test_a_record_helper_for_one_array_type_does_not_attach_to_another_fail;
{$mode delphi}{$modeswitch typehelpers}
{ %FAIL: a helper attaches to the NAMED array type, never to its shape.

  This is the control that makes the array-helper fix correct rather than merely
  working. TA and TB have identical element type, identical dynamic-ness and
  identical depth -- a symbol records an array's SHAPE and not its IDENTITY, so
  the obvious implementation (match a helper by element kind and depth) compiles
  this file and is WRONG. Hence SymArrAi and UClsHelperArrAi, both keyed on the
  ArrType ROW.
  bug-p-self-in-a-record-helper-for-a-dynamic-array-types-as-integer }
type
  TA = array of LongInt;
  TB = array of LongInt;
  TAHelper = record helper for TA
    function Cnt: LongInt;
  end;
function TAHelper.Cnt: LongInt;
begin
  Result := Length(Self);
end;
var b: TB;
begin
  SetLength(b, 3);
  WriteLn(b.Cnt);      { TB has no helper -> must be refused }
end.
