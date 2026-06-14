program test_varrec_string;

{ Regression: a vtAnsiString element of an `array of const`. A frozen string
  literal value points at its 8-byte length prefix (skip +8 for the char data);
  a runtime AnsiString value is ALREADY a char pointer (matches PChar(s)), so it
  must be stored as-is. Previously the +8 skip was applied to both, so variable /
  parameter / concat string elements landed mid-string (garbage). Mix in an
  integer to confirm tag dispatch is unaffected. }

procedure dump(const items: array of const);
var i: Integer;
begin
  for i := 0 to Length(items) - 1 do
  begin
    if items[i].VType = vtAnsiString then writeln('S=', PChar(items[i].VAnsiString))
    else if items[i].VType = vtInteger then writeln('I=', items[i].VInteger)
    else writeln('?');
  end;
end;

procedure viaparam(const p: AnsiString);
begin
  dump([p, 'tail']);
end;

var s, t: AnsiString;
begin
  s := 'hello';
  t := 'wor';
  dump(['lit', 42, s, t + 'ld']);
  viaparam('param');
end.
