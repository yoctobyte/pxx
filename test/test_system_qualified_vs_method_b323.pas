{ `System.X(...)` must beat a same-named METHOD of the enclosing class (b323).

  The implicit-Self shadow-clear treated the System qualifier (qUnit = -2) like a
  bare name, so inside a class with its own `Delete(Index: Integer)`,
  `System.Delete(E, 1, P)` dispatched to the METHOD with mangled arguments —
  fpjson's TJSONArray.DoFindPath crashed on FList through Self=1. Statement and
  expression sides both fixed (qUnit = -1 only). Verified against FPC: the
  qualified call always names the RTL routine. }
program test_system_qualified_vs_method_b323;
{$mode objfpc}{$h+}
uses SysUtils;

type
  TBox = class
    procedure Delete(Index: Integer);
    function Go(const APath: String): String;
  end;

procedure TBox.Delete(Index: Integer);
begin
  Writeln('method Delete(', Index, ')');
end;

function TBox.Go(const APath: String): String;
var
  E: String;
  P: Integer;
begin
  E := APath;
  P := 3;
  System.Delete(E, 1, P);
  Result := E;
end;

var
  B: TBox;
begin
  B := TBox.Create;
  Writeln('got=', B.Go('abcdef'));
  B.Delete(7);   { the method still reachable bare }
end.
