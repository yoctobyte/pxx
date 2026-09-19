program test_unwinder_skips_a_dead_frame;
{ The x86-64 unwinder's stale-frame walk (exception_emit.inc), which had no row
  of its own. Built with PXXDBG=a.gotocross, the fault injection that lets the
  `goto` in LeaveADeadFrame out of its `try` -- the one way left to put a DEAD
  frame on the chain on purpose, since the compiler now refuses that goto.

  The stack under the dead frame is overwritten with small non-zero words
  before the raise, so the frame fails validation and its link is garbage (32).
  The walk must NOT follow that link -- it does not point up -- and must reach
  the unhandled path, which prints. Pin v412 followed it and faulted in
  `mov rdx, [rax+56]`: the skip message, then SIGSEGV, and no "Unhandled
  exception" line. Main's own `try` is live and is NOT reached: once the chain
  is known broken, ending with the message is the goal, not a guessed landing.

  WHAT THIS CANNOT TEST, BECAUSE THE UNWINDER CANNOT SEE IT: a dead frame whose
  memory survived intact still satisfies the saved-rsp equality, so it is
  jumped into as if live. No content check tells the two apart, and a position
  check is unsound across a generator's stack, so the defence there is to not
  leave the frame -- which is what the goto refusal does for this route.

  bug-a-something-in-lekkerzeilen-s-startup-still-leaves-an-exception-frame-on-the-chain }
{$mode objfpc}
uses sysutils;

procedure LeaveADeadFrame;
label l;
begin
  try
    goto l;
  except
  end;
  l:
end;

{ The dead frame sits two 4 KB frames down so that Clobber, and not whatever
  Exception.Create and the raise helper happen to leave on the same stack,
  decides what its memory holds. }
procedure Descend(n: Integer);
var pad: array[0..511] of Int64;
begin
  pad[n] := n;
  if n > 0 then Descend(n - 1) else LeaveADeadFrame;
  if pad[n] <> n then writeln('unreachable');
end;

procedure Clobber(n: Integer);
var pad: array[0..511] of Int64; i: Integer;
begin
  for i := 0 to 511 do pad[i] := 32;
  if n > 0 then Clobber(n - 1);
  if pad[0] <> 32 then writeln('unreachable');
end;

procedure Main;
begin
  try
    Descend(2);
    Clobber(8);
    raise Exception.Create('after a dead frame');
  except
    on E: Exception do
      writeln('caught');
  end;
end;

begin
  Main;
end.
