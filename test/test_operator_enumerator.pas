program test_operator_enumerator;
{ `operator enumerator (c: TCont): TEnum` drives for-in via the duck-typed
  MoveNext/Current protocol (tforin5 shape). }
type
  TMyList = class
    Vals: array[0..2] of Integer;
  end;
  TMyListEnumerator = class
  public
    FList: TMyList;
    FCurrent: Integer;
    function GetCurrent: Integer;
    function MoveNext: Boolean;
    property Current: Integer read GetCurrent;
  end;
function TMyListEnumerator.GetCurrent: Integer;
begin
  Result := FList.Vals[FCurrent];
end;
function TMyListEnumerator.MoveNext: Boolean;
begin
  Inc(FCurrent);
  Result := FCurrent <= 2;
end;
operator enumerator(AList: TMyList): TMyListEnumerator;
begin
  Result := TMyListEnumerator.Create;
  Result.FList := AList;
  Result.FCurrent := -1;
end;
var
  l: TMyList;
  i: Integer;
begin
  l := TMyList.Create;
  l.Vals[0] := 10; l.Vals[1] := 20; l.Vals[2] := 30;
  for i in l do
    writeln(i);
end.
