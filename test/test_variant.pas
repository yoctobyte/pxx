program test_variant;
{ Phase 1 scalar Variant smoke test: box int / int64 / char / double / bool
  into a tyVariant slot, reassign across types, copy variant-to-variant, and
  read back via writeln tag dispatch. Strings deferred (managed AnsiString). }
var
  v, w: Variant;
begin
  v := 42;
  writeln(v);          { 42 }

  v := -7;
  writeln(v);          { -7  (sign-extended payload) }

  v := 'Q';
  writeln(v);          { Q }

  v := 3.14;
  writeln(v);          { 3.14e+00-ish via float writer }

  v := True;
  writeln(v);          { 1  (booleans print as 0/1 in this dialect) }

  v := 100;
  w := v;              { variant-to-variant 16-byte copy }
  writeln(w);          { 100 }
end.
