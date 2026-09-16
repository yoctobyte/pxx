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

{ Three routines the PROGRAM hides behind a constant of the same name, which is
  what fpc's own cfileutl.pas:142 does to SysUtils.ExecuteProcess and then calls
  qualified anyway. The qualifier was consulted by the proc table and by neither
  constant table, so the constant took the call and the ARGUMENTS WERE DISCARDED.
  Each returns Value + a distinct base, so a row that resolved to the constant
  cannot accidentally print the right number.
  bug-p-a-unit-qualified-reference-is-captured-by-a-same-named-string-const }
function Hidden(Value: Integer): Integer;
function HiddenSet(Value: Integer): Integer;
function HiddenEmpty(Value: Integer): Integer;

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

function Hidden(Value: Integer): Integer;
begin
  Result := Value + 500;
end;

function HiddenSet(Value: Integer): Integer;
begin
  Result := Value + 600;
end;

function HiddenEmpty(Value: Integer): Integer;
begin
  Result := Value + 700;
end;

end.
