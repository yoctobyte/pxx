program TestForInEnumerator;
{$mode objfpc}
type
  TIntEnumerator = class
    Items: array[0..2] of Integer;
    Idx: Integer;
    FCurrent: Integer;
    function MoveNext: Boolean;
    property Current: Integer read FCurrent;
  end;
  TIntColl = class
    function GetEnumerator: TIntEnumerator;
  end;

function TIntEnumerator.MoveNext: Boolean;
begin
  if Self.Idx < 3 then
  begin
    Self.FCurrent := Self.Items[Self.Idx];
    Self.Idx := Self.Idx + 1;
    Result := True;
  end
  else
    Result := False;
end;

function TIntColl.GetEnumerator: TIntEnumerator;
var e: TIntEnumerator;
begin
  e := TIntEnumerator.Create;
  e.Items[0] := 11; e.Items[1] := 22; e.Items[2] := 33;
  e.Idx := 0;
  Result := e;
end;

var
  coll: TIntColl;
  x, sum: Integer;
begin
  coll := TIntColl.Create;
  sum := 0;
  for x in coll do
  begin
    writeln('x=', x);
    sum := sum + x;
  end;
  writeln('sum=', sum);
end.
