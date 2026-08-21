program test_nil_check_catchable;
{ The payload of feature-a-emitted-nil-checks, and the reason it is not "a nicer
  message": with sysutils in, the nil-reference trap RAISES, so `try..except on
  E: EAccessViolation` runs and the program CARRIES ON.

  --fpc-mem-errors cannot do this and never will. It reports a fault from a
  signal handler, after the process is already dead — there is nothing to unwind
  to and no line to name. The difference between the two mechanisms is this
  test's third line.

  EAccessViolation has been declared in sysutils since the exception hierarchy
  landed and had nothing to raise it until now.
  feature-a-emitted-nil-checks }
uses SysUtils;
type TProc = procedure;
var f: TProc;
begin
  writeln('before');
  f := nil;
  try
    f();
    writeln('NOT REACHED');
  except
    on E: EAccessViolation do writeln('caught: ', E.Message);
  end;
  writeln('still running');
end.
