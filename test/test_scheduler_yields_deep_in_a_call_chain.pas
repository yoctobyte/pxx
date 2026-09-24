program TestSchedulerYieldsDeepInACallChain;
{ Coroutines that YIELD FROM DEEP INSIDE A CALL CHAIN, interleaved, with small
  explicit stacks.

  Written for the xtensa WINDOWED CoSwitch (coroutine_emit.inc): there a
  caller's registers live in a rotating register window, not on the stack, so
  a switch must spill every live window to its own stack and the resume must
  reload them from the OTHER stack through the window-underflow handler. A
  shallow yield -- one frame below the entry -- barely exercises that, because
  the chip holds 64 registers and a few frames never overflow. Recursing twenty
  deep before each yield puts far more live frames in flight than the register
  file holds, so every switch crosses spilled frames in both directions, and a
  value carried in each frame (`depth`, `acc`) is checked on the way back up.
  A try/except that spans a yield checks that each coroutine keeps its own
  exception chain (BSS_EXC_TOP travels with the stack).

  SpawnSized and not Spawn: the default 192 KB coroutine stack does not fit
  three times in an ESP32-S3's internal RAM, and this file is also run on the
  board. Asserted against the x86-64 build of the same source. }
uses sysutils, scheduler;

function Dive(tag, depth, acc: Integer): Integer;
begin
  if depth = 0 then
  begin
    CoYield;                          { switch away with 20 frames live }
    Result := acc;
    Exit;
  end;
  Result := Dive(tag, depth - 1, acc + depth * tag) + 1;
  if depth mod 7 = 0 then CoYield;    { and again on the way back up }
end;

procedure Worker(arg: Pointer);
var tag, r, round: Integer;
begin
  tag := Integer(arg);
  for round := 1 to 3 do
  begin
    r := Dive(tag, 20, round);
    writeln('w', tag, ' round ', round, ' = ', r);
  end;
end;

procedure Raiser(arg: Pointer);
begin
  try
    CoYield;
    Dive(5, 12, 0);
    raise Exception.Create('from coroutine ' + IntToStr(Integer(arg)));
  except
    on E: Exception do writeln('caught: ', E.Message);
  end;
end;

begin
  SpawnSized(@Worker, Pointer(1), 16384);
  SpawnSized(@Worker, Pointer(2), 16384);
  SpawnSized(@Raiser, Pointer(9), 16384);
  RunUntilDone;
  writeln('all done');
end.
