program test_xtensa_finalizer_call_reach;
{ THE FORWARD CALL EVERY EXIT PATH MAKES, on the one target where it can fail to
  reach. EmitProgramEpilogue emits the __pxx_run_finalizers body AFTER the main
  body, while every exit path emits a FORWARD call to it -- including the
  earliest. Its displacement is therefore (end of program - call site), so on
  xtensa the first Halt site in any image over ~512 KiB of code cannot reach it
  with a 3-byte CALL0/CALL8.

  That is why the wall read as "programs over 512 KiB" for every program shape,
  why an unrelated RTL edit could flip an image that built the day before, and
  why all three known failures named this one proc.

  This program is nothing special -- `uses sysutils` plus one try/except is as
  ordinary as Pascal on this target gets -- and that IS the point: it is over
  the wall at ~651 KB of code. The Makefile row builds it for xtensa WITHOUT
  --xtensa-long-calls. Before the fix that was a hard compile error; the row is
  therefore a real guard and not a formality.

  Output is compared against the SAME program built natively rather than a
  literal, so the row carries no per-target constant. }
uses sysutils;
var
  n: Integer;
begin
  n := 0;
  try
    raise Exception.Create('boom');
  except
    on E: Exception do
    begin
      writeln('caught ', E.Message);
      n := n + 1;
    end;
  end;
  writeln('handlers=', n);
  writeln('done');
end.
