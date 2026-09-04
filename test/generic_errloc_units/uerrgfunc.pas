{ A generic ROUTINE whose body is wrong only after substitution, in a UNIT.
  Subject of the file-attribution arm of test_generic_error_location_names_a_
  third_file_fail: the specialization splices this body into the PROGRAM's
  token stream, and the diagnostic must still name THIS file.

  GenericFuncs[] is the third kind of region in the template arena, and
  TemplateSrcKeyOfTok did not scan it -- deliberately, with the reason written
  down: a `generic function` could not be declared in a unit at all, so a
  routine body never crossed a file boundary. The moment
  bug-p-a-generic-function-cannot-be-declared-in-a-unit made the declaration
  legal that reason expired: measured, the error below printed its line number
  with NO `in:` line at all, which reads as that line of the six-line PROGRAM.
  The LINE was right and the FILE was missing, which is the failure mode that
  does not look like one. }
unit uerrgfunc;
{$mode objfpc}

interface

generic function BadBody<T>(a: T): T;

implementation

generic function BadBody<T>(a: T): T;
begin
  Result := a.NoSuchMemberAnywhere;
end;

end.
