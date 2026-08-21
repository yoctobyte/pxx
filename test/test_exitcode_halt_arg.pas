{ Halt(n) sets ExitCode := n BEFORE the finalizations, which is what lets one
  inspect it. 100 -> the finalization zeroes it -> the process succeeds. That
  ordering is the feature: terminating with the ARGUMENT would make the
  finalization's write invisible and this would exit 100. FPC 3.2.2: exit 0. }
program test_exitcode_halt_arg;
uses uexit;
begin
  writeln('body');
  Halt(100);
end.
