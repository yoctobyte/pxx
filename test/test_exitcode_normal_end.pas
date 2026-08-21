{ Falling off the end of main is FPC's Halt(ExitCode): the finalization runs and
  the process exits with what the finalization LEAVES in ExitCode. Here the body
  sets 9, the finalization sees 9 and stores 10, so the process exits 10 -- an
  exit status the body never wrote. FPC 3.2.2: same. }
program test_exitcode_normal_end;
uses uexit;
begin
  writeln('body');
  ExitCode := 9;
end.
