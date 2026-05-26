program test_class_methods;
type
  TCounter = class
    Value : Integer;
    procedure Reset;
    procedure Increment;
    function  Get: Integer;
  end;

procedure TCounter.Reset;
begin
  Self.Value := 0;
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
  c := TCounter.Create;
  c.Reset;
  c.Increment;
  c.Increment;
  c.Increment;
  writeln(c.Get);
end.
