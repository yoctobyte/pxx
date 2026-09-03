{ NEGATIVE HALF of test_pascal_varargs_external: accepting a variadic tail must
  not accept EVERY extra argument. `fflush` has no `varargs`, so a second
  argument has no parameter to match and the call must be REFUSED -- fpc 3.2.2
  refuses the same line ("Wrong number of parameters specified for call to
  fflush"). Without this row the arity clause could be written as "any nArgs
  >= ParamCount matches" and the suite would not notice.
  bug-a-a-c-headers-variadic-tail-is-dropped-on-import }
program pascal_varargs_not_declared_rejected;
function fflush(f: Pointer): Integer; cdecl; external 'libc.so.6';
begin
  writeln(fflush(nil, 1));
end.
