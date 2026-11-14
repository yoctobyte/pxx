program TestSchedulerExcDynamic;
{ Cross-coroutine exception safety: each coroutine wraps a CoYield in a
  try/except and raises after resuming. Because the setjmp exception-chain head
  (BSS_EXC_TOP) is per-stack and CoSwitch saves/restores it, two interleaved
  coroutines each catch their OWN exception — without the swap, one's try-frame
  would sit on the other's chain and a raise would unwind the wrong frames.
  x86-64 only for now.

  THIS COPY LINKS LIBC (getpid), so the gs block carries an owner marker
  (TLS_SLOT_OWNER_FS) and every `try` entry checks it. The coroutines run on
  heap stacks, which is what defeated every address-based marker; the fs
  marker must not read them as foreign threads. A re-adoption on a coroutine
  entry would zero the chain the CoSwitch swap keeps, and `w1 caught` would
  not print.
  decide-a-a-foreign-thread-needs-its-own-tls-block-and-the-bounds-are-the-hard-part }
uses scheduler;
function getpid: Integer; cdecl; external 'libc.so.6';

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
  if getpid <= 0 then writeln('pid?');
  Spawn(@W, Pointer(1));
  Spawn(@W, Pointer(2));
  RunUntilDone;
  writeln('done');
end.
