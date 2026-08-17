unit qualified_a;

interface

const
  SharedConst = 1074030207;
  { An untyped STRING const, reached qualified while the program declares a
    variable of the same name. Its own table is not scoped, so a same-named
    variable used to cancel it — including for an explicitly qualified read.
    bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails }
  SharedTag = 'from-unit';

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
