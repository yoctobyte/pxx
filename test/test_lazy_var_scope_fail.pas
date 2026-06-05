program test_lazy_var_scope_fail;

begin
  begin
    var a := 42;
  end;
  writeln(a);
end.
