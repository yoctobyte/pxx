{ Regression: bug-pascal-unicodestring-widestring-type-missing —
  unicodestring/widestring alias the native string type (byte semantics):
  literals, writeln, Length, indexing, comparison, concat, case-of. The real
  UTF-16 payload model is a documented later slice. }
program test_unicodestring_alias;
var w: widestring; u: unicodestring; c: Integer;
begin
  w := 'abc';
  u := 'hello';
  writeln(w);                    { abc }
  writeln(u);                    { hello }
  writeln(Length(u));            { 5 }
  writeln(u[2]);                 { e }
  if w = 'abc' then writeln('eq');
  u := u + '!';
  writeln(u);                    { hello! }
  c := 0;
  case u of
    'nope': c := 1;
    'hello!': c := 2;
  else c := 3;
  end;
  writeln(c);                    { 2 }
end.
