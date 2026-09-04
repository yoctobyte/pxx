{ NEGATIVE test: this must NOT compile, and the diagnostic must name the UNIT
  the offending code was written in -- not this program, into whose token stream
  the specialized body is spliced.

  A generic ROUTINE's buffered body is the third kind of region in the template
  arena (Templates[], GenericMethods[], GenericFuncs[]), and TemplateSrcKeyOfTok
  scanned the first two. See uerrgfunc.pas for why that was correct until it
  was not. bug-p-a-generic-function-cannot-be-declared-in-a-unit }
program test_generic_func_error_names_its_unit_fail;
{$mode objfpc}
uses uerrgfunc;
begin
  writeln(specialize BadBody<Integer>(1));
end.
