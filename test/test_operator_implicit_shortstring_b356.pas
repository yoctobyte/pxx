program TestOperatorImplicitShortString;
{$mode delphi}
{ Regression: a `class operator Implicit(...): string[N]` must be INVOKED at an
  implicit assignment `s := t`. The result-type match keyed on exact TypeKind, but
  `string[N]` resolves to tyString in a var decl and tyFixedString as an operator
  return — so the operator was never found, `s := t` fell through to a raw
  record->string store, and the shortstring's garbage length byte segfaulted at
  the next read (toperator93). }
type
  TString80 = String[80];
  TTest = record
    Val: Integer;
    class operator Implicit(const aArg: TTest): TString80;
  end;

class operator TTest.Implicit(const aArg: TTest): TString80;
begin
  Result := 'converted:';
  if aArg.Val = 7 then Result := 'seven';
end;

var
  t: TTest;
  s: TString80;
begin
  t.Val := 7;
  s := t;                 { implicit operator TTest -> String[80] }
  WriteLn(s);             { seven }
  t.Val := 1;
  s := t;
  WriteLn(s, ' len=', Length(s));   { converted: len=10 }
end.
