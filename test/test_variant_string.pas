{$define PXX_MANAGED_STRING}
program test_variant_string;

var
  v, w: Variant;
  s: AnsiString;

procedure CheckLocal;
var local: Variant;
begin
  local := 'local';
  writeln(local);
  local := 7;
  writeln(local);
end;

begin
  v := 'hello';
  writeln(v);

  w := v;
  v := 42;
  writeln(v);
  writeln(w);

  s := 'managed';
  v := s;
  s := 'changed';
  writeln(v);

  w := 'world';
  writeln(w);
  CheckLocal;
end.
