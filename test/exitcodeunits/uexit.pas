unit uexit;
{ The observer half of test_exitcode_*.pas. Its finalization does the two things
  FPC's erroru.pp does and that the whole feature exists for: it READS ExitCode
  (so the value Halt set must already be there) and then WRITES it (so the
  process must exit with the value it leaves behind, not the one Halt was
  given). 100 -> 0 is erroru's own idiom: an expected halt(100) becomes a
  successful process. }
interface
implementation
initialization
  writeln('init');
finalization
  writeln('fini sees ', ExitCode);
  if ExitCode = 100 then ExitCode := 0 else ExitCode := ExitCode + 1;
end.
