program TestCaseElseMultistmt;
{ Regression for bug-case-else-multi-statement-parse-error: a `case...else`
  clause with more than one bare statement (no begin/end) before `end` used
  to be parsed as a single statement, desyncing the parser and producing a
  confusing "expected end" error far from the real cause. `else` takes an
  implicit statement LIST up to `end`, same as try/except's handler list. }
function Foo(x: Integer; var text: AnsiString): Integer;
begin
  case x of
    0: text := 'a';
    1: begin text := 'b'; Result := 1; Exit; end;
  else
    text := 'c'; Result := 4; Exit;
  end;
  Result := 5;
end;

var t: AnsiString;
begin
  writeln(Foo(0, t), ' ', t);
  writeln(Foo(1, t), ' ', t);
  writeln(Foo(9, t), ' ', t);
end.
