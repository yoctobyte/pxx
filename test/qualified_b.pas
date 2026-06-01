unit qualified_b;

interface

var
  SharedValue: Integer;

function SharedFunc: Integer;
function SharedAdd(Value: Integer): Integer;
procedure SetShared(Value: Integer);

implementation

function SharedFunc: Integer;
begin
  Result := 22;
end;

function SharedAdd(Value: Integer): Integer;
begin
  Result := Value + 200;
end;

procedure SetShared(Value: Integer);
begin
  SharedValue := Value;
end;

end.
