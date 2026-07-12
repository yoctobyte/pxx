program test_with_class_create;
{ `with TFoo.Create do` — operand evaluates ONCE (materialised temp);
  with-scoped property writes/reads, bare methods, and builtin Free all
  resolve (ftpsend's helper pattern). }
type
  TFoo = class
  private
    FBar: Integer;
  public
    Created: Integer;
    constructor Create;
    function GetDouble: Integer;
    property Bar: Integer read FBar write FBar;
  end;
var mkCount: Integer;
constructor TFoo.Create;
begin
  Inc(mkCount);
end;
function TFoo.GetDouble: Integer;
begin
  Result := FBar * 2;
end;
begin
  mkCount := 0;
  with TFoo.Create do
  begin
    Bar := 21;
    writeln(Bar);
    writeln(GetDouble);
    Free;
  end;
  writeln('creates=', mkCount);
end.
