program test_xtensa_init_locals;
{ A unit's initialization section with its own locals (32-bit, string, Int64)
  and a finalization that prints. Both are synthesized procs with a prologue
  of their own (ParseInitializationSection), separate from the one every other
  body gets, so the windowed frame-pointer bias (XT_FP_BIAS) has to be applied
  there too or every local in them is read 64 bytes off. Prints the same on x64. }
uses test_xtensa_init_locals_unit;
begin
  writeln(G, ' ', GS);
end.
