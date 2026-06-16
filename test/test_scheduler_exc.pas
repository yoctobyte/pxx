program TestSchedulerExc;
{ Cross-coroutine exception safety: each coroutine wraps a CoYield in a
  try/except and raises after resuming. Because the setjmp exception-chain head
  (BSS_EXC_TOP) is per-stack and CoSwitch saves/restores it, two interleaved
  coroutines each catch their OWN exception — without the swap, one's try-frame
  would sit on the other's chain and a raise would unwind the wrong frames.
  x86-64 only for now. }
uses scheduler;

procedure W(arg: Pointer);
var n: Integer;
begin
  n := Integer(arg);
  try
    writeln('w', n, ' try');
    CoYield;
    raise n;
    writeln('w', n, ' UNREACHED');
  except
    writeln('w', n, ' caught');
  end;
end;

begin
  Spawn(@W, Pointer(1));
  Spawn(@W, Pointer(2));
  RunUntilDone;
  writeln('done');
end.
