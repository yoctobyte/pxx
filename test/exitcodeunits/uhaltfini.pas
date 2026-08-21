unit uhaltfini;
{ A finalization that itself calls Halt. The finalization runner is run-once
  guarded, so this Halt does NOT re-enter the finalizations -- it exits
  immediately with its own code, discarding the ExitCode the body set. FPC
  3.2.2 does the same (exit 77 with a body that stored 4). Without the guard
  this would recurse until the stack ran out. }
interface
implementation
initialization
finalization
  Halt(77);
end.
