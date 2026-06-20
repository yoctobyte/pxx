program test_method_implicit_field;

{ Implicit-Self field access inside methods for the array intrinsics. Length,
  SetLength and High must resolve an unqualified class field (`Items`) the same
  way an explicitly-qualified `Self.Items` does. Regression for the bug where
  Length/High errored ('undefined variable') on an implicit-Self dynamic-array
  field even though ParseLValueAST had already resolved it. A scalar field is
  exercised too so the fix does not disturb non-array implicit-Self use. }

{$define PXX_MANAGED_STRING}

type
  TObj = class
    Items: array of Integer;
    FCount: Integer;
    procedure Grow(n: Integer);
    function Len: Integer;
    function Hi: Integer;
    function CountPlusOne: Integer;
  end;

procedure TObj.Grow(n: Integer);   { unqualified SetLength on a field }
begin
  SetLength(Items, n);
end;

function TObj.Len: Integer;        { unqualified Length on a field }
begin
  Result := Length(Items);
end;

function TObj.Hi: Integer;         { unqualified High on a field }
begin
  Result := High(Items);
end;

function TObj.CountPlusOne: Integer;  { scalar implicit-Self field, no array }
begin
  Result := FCount + 1;
end;

var o: TObj;
begin
  o := TObj.Create;
  o.FCount := 41;
  o.Grow(3);
  Writeln(o.Len);            { 3 }
  Writeln(o.Hi);             { 2 }
  Writeln(o.CountPlusOne);   { 42 }
  o.Grow(0);
  Writeln(o.Len);            { 0 }
  Writeln(o.Hi);             { -1 }
end.
