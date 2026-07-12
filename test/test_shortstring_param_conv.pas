program test_shortstring_param_conv;
{ A managed (AnsiString) argument to a Const ShortString param converts
  through a hidden frozen temp (Pascal Script's CheckReserved shape).
  writeln(S) itself is still broken for shortstring params — tracked in
  bug-pascal-writeln-shortstring-param — so assert via Length + compare. }
procedure Check(const S: ShortString; var flag: Boolean);
begin
  flag := (Length(S) = 5) and (S = 'HELLO');
end;
var m: AnsiString; ok: Boolean;
begin
  m := 'HELLO';
  Check(m, ok);
  writeln(ok);
end.
