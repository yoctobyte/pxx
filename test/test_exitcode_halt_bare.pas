{ A bare `Halt` is Halt(0) -- it RESETS ExitCode, it does not "exit with the
  current one". Measured against FPC 3.2.2, which contradicted the ticket:
  the finalization here sees 0, not the 9 the body just stored, so the process
  exits 1. Getting this backwards is invisible in every program that does not
  set ExitCode first, which is why it has its own test. }
program test_exitcode_halt_bare;
uses uexit;
begin
  writeln('body');
  ExitCode := 9;
  Halt;
end.
