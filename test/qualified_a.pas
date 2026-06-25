unit qualified_a;

interface

const
  SharedConst = 1074030207;

var
  SharedValue: Integer;

function SharedFunc: Integer;
function SharedAdd(Value: Integer): Integer;
procedure SetShared(Value: Integer);

implementation

function SharedFunc: Integer;
begin
  Result := 11;
end;

function SharedAdd(Value: Integer): Integer;
begin
  Result := Value + 100;
end;

procedure SetShared(Value: Integer);
begin
  SharedValue := Value;
end;

end.
