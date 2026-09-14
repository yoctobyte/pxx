program test_weakexternal_hard;
{ THE CONTROL for the two tests beside this one: plain `external` of a symbol
  nothing defines must STILL be a fatal startup failure. Without this row,
  "weakexternal works" is satisfied by a compiler that made every import weak.
  Asserted in the Makefile by its nonzero exit and its loader message -- this
  program never reaches its own begin.
  feature-a-optional-imports-an-undefined-weak-dynamic-symbol }
function nosuchfunc_pxx_probe(x: Integer): Integer; cdecl;
  external 'libc.so.6' name 'nosuchfunc_pxx_probe';
begin
  Writeln('UNREACHABLE: ', nosuchfunc_pxx_probe(1));
end.
