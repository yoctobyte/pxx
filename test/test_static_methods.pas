program test_static_methods;
type
  TCounter = class
    Value : Integer;
    class function Add(a, b: Integer): Integer;
    procedure Increment;
    function Get: Integer;
  end;

class function TCounter.Add(a, b: Integer): Integer;
begin
  Result := a + b;
end;

procedure TCounter.Increment;
begin
  Self.Value := Self.Value + 1;
end;

function TCounter.Get: Integer;
begin
  Result := Self.Value;
end;

var c: TCounter;
begin
  writeln(TCounter.Add(3, 4));
  c := TCounter.Create;
  c.Value := 10;
  c.Increment;
  writeln(c.Get);
  writeln(c.Add(20, 5));
end.
