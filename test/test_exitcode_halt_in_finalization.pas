{ See test/exitcodeunits/uhaltfini.pas: a Halt reached from INSIDE a
  finalization exits with its own code and does not re-enter the finalization
  runner, whose run-once guard is what makes that terminate at all. The body's
  ExitCode := 4 is discarded. FPC 3.2.2: exit 77. }
program test_exitcode_halt_in_finalization;
uses uhaltfini;
begin
  writeln('body');
  ExitCode := 4;
end.
