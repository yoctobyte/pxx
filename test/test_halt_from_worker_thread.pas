program test_halt_from_worker_thread;
{ `Halt(n)` from a NON-MAIN thread must end the PROCESS, not just that thread.

  x86-64 and arm32 emitted the `exit` syscall here instead of `exit_group`, so a
  worker's fatal killed only the worker; the process then carried on and its
  status fell to whichever thread exited LAST — and a thread finishing normally
  exits 0. A fatal that reports SUCCESS.
  bug-b-concurrent-halt-from-several-threads-exits-0

  THE SHAPE OF THIS TEST IS THE POINT, and it is the opposite of a minimal repro.
  The tidy version — N threads each calling Halt(n), all joined by main — CANNOT
  fail: the joins order the exits and make main last by construction, so the
  status survives whichever syscall Halt used. Six such threads exited 216 six
  times out of six with the bug fully present, and that green stalled the
  original diagnosis. When the defect IS the disorder, minimising removes it.

  So: nobody joins the worker, and the question is not "what status do we get"
  but "does the process die at all". That makes it deterministic rather than
  racy — the earlier investigation's table was 3 samples per cell of a race, and
  read as a rule that was not there.

  Verified both ways before landing: 10/10 exit 216 with the fix, 10/10 print the
  marker and exit 3 without it, on x86-64 and arm32 alike. }
uses palthread;

var
  reached: Int64;

procedure Halter(arg: Pointer);
begin
  writeln('worker: calling Halt(216)');
  reached := 1;
  Halt(216);
end;

var
  h: TThreadHandle;
  rc: Integer;
  spin: Int64;
begin
  reached := 0;
  rc := PalThreadCreate(h, @Halter, Pointer(0), 0);
  if rc <> 0 then begin writeln('spawn failed'); Halt(1); end;

  { Wait until the worker is provably at its Halt, so this does not depend on
    the scheduler getting there first — then outlive it WITHOUT joining. If
    Halt only ended the calling thread, control reaches the marker below. }
  while reached = 0 do ;
  spin := 0;
  while spin < 800000000 do spin := spin + 1;

  writeln('BUG: main outlived a worker''s Halt(216)');
  Halt(3);
end.
