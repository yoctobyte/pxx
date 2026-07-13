{ A SELECTOR after a function call used as a STATEMENT was silently DROPPED.

  `GetBox.Poke;` / `GetBox.SetVal(42);` / `GetBox.Val := 5;` / `GetBoxAt(0).M(...)`
  all parsed the bare call (or, with parens, the call and its args) and left the
  trailing `.member` in the token stream — where ParseStatementAST's default branch
  skipped it to the next ';' with NO diagnostic. The whole statement vanished:
  fpjson's testregistry registered 0 of its 203 tests through exactly this shape
  (`GetTestRegistry.AddTestSuiteFromClass(ATestClass)` inside RegisterTest).

  The statement path now detects a '.' after the callee name (or after the matching
  ')' of its argument list) and hands the full chain to the expression parser; a
  trailing `:=` becomes a store through the result's member. Verified against FPC. }
program test_stmt_call_result_selector_b318;
{$mode objfpc}{$h+}
type
  TBox = class
  public
    Val: Integer;
    procedure SetVal(A: Integer);
    procedure Poke;
    function GetVal: Integer;
  end;

procedure TBox.SetVal(A: Integer); begin Val := A; end;
procedure TBox.Poke; begin Writeln('poke val=', Val); end;
function TBox.GetVal: Integer; begin Result := Val; end;

var
  G: TBox;

function GetBox: TBox;
begin
  if G = nil then G := TBox.Create;
  Result := G;
end;

function GetBoxAt(I: Integer): TBox;
begin
  Result := GetBox;
end;

begin
  GetBox.Poke;                 { paramless callee, void method on result }
  GetBox.SetVal(42);           { paramless callee, method-with-arg }
  Writeln('a=', G.Val);
  GetBox.Val := 5;             { store through the result's field }
  Writeln('b=', G.Val);
  GetBoxAt(0).SetVal(7);       { callee WITH args, then a method on its result }
  Writeln('c=', G.Val);
  Writeln('d=', GetBoxAt(0).GetVal);  { expression position stays intact }
end.
