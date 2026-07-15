program TestForInRecordEnumerator;
{$mode objfpc}{$modeswitch advancedrecords}
{ Regression: a RECORD enumerator (FPC advancedrecords: GetEnumerator returns a
  record by value) must be held as an embedded record value in the for-in
  desugar — Self = @record, `__e := C.GetEnumerator` is a record-copy — not as a
  tyClass pointer. It also exercises Length() of a static-array RECORD FIELD,
  which must fold to the field's count (a static array carries no runtime header).
  Both were broken: the enumerator was modelled as a pointer AND Length(FArr)
  returned 0, so `for I in Arr` ran zero iterations (tforin25). }
type
  TEnum = record
    FIndex: Integer;
    FArr: array[0..3] of Integer;
    function MoveNext: Boolean;
    function GetCurrent: Integer;
    property Current: Integer read GetCurrent;
  end;
  TMy = record
    F: array[0..3] of Integer;
    function GetEnumerator: TEnum;
  end;

function TEnum.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := FIndex < Length(FArr);   { Length of a static-array field: must be 4 }
end;

function TEnum.GetCurrent: Integer;
begin
  Result := FArr[FIndex];
end;

function TMy.GetEnumerator: TEnum;
begin
  Result.FArr := F;
  Result.FIndex := -1;
end;

var
  a: TMy;
  i, n: Integer;
begin
  a.F[0] := 10; a.F[1] := 20; a.F[2] := 30; a.F[3] := 40;
  n := 0;
  for i in a do
  begin
    WriteLn('i=', i);
    n := n + i;
  end;
  WriteLn('sum=', n);
end.
