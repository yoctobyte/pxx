program test_typed_string_const;
{ bug-string-const-index-and-typed-init: `const Name: string = 'literal'` (typed
  string constant with a string initializer) parses and reads back, including the
  concat forms, indexing, assignment and Length. Treated as a read-only literal
  alias (StrConst table), like the untyped `const Name = 'literal'`. }
const
  t: string = 'ABCDEF';
  u: string = 'foo' + 'bar';
  v: string = #65 + 'BC';

procedure Local;
const w: string = 'local!';
begin
  writeln(w);
end;

var
  s: string;
begin
  writeln(t);
  writeln(u);
  writeln(v);
  writeln(t[2]);
  s := t;
  writeln(s);
  writeln(Length(t));
  Local;
end.
