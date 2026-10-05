program test_c_import_extern_vars;
{ `extern` variables of a `uses`-imported C header: visible from a routine
  body (the header's tokens follow the program's, which the declare-before-use
  stamp read as "declared later"), read and written through fields, and bound
  to the C definitions at link. Built with --emit-obj; c_import_extern_vars_def.c
  defines them and calls show. }
uses c_import_extern_vars;

procedure show; cdecl;
var p: ^pair_t;
begin
  p := @g_pair;
  writeln(p^.a, ' ', p^.b, ' ', g_pair.b, ' ', g_cpair.b, ' ', g_int);
  g_pair.b := 77;
end;

begin
end.
