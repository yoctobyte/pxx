{ FreeOnTerminate threads must not leak, even when nobody calls CheckSynchronize.

  A self-freeing thread cannot free the handle it is standing on, because the
  kernel writes TidWord at thread exit. palthreadobj parked the handle for
  CheckSynchronize to join and free. A console program that never calls that
  (FPC needs no such call) kept two blocks and a stack mapping per thread:
  measured 2026-09-25 at pin v425, live 201 at 100 threads and 2001 at 1000.
  The handle now goes to the PAL (PalThreadRelease), which frees it once the
  kernel reports the thread dead.

  Built -dPXX_ALLOC_CENSUS and bounded by tools/assert_no_leak.sh. 600 threads
  leaked about 1200 blocks before the fix. }
program test_freeonterminate_threads_give_their_handles_back;
{$mode objfpc}
uses palthreadobj, palsync, sysutils;

var cs: TRTLCriticalSection; done: Integer;

type TW = class(TThread) procedure Execute; override; end;
procedure TW.Execute;
begin
  EnterCriticalSection(cs); done := done + 1; LeaveCriticalSection(cs);
end;

var i, k, target: Integer; t: TW;
begin
  InitCriticalSection(cs); done := 0; i := 0;
  while i < 600 do
  begin
    for k := 0 to 9 do begin t := TW.Create(True); t.FreeOnTerminate := True; t.Start; end;
    i := i + 10; target := i;
    repeat
      EnterCriticalSection(cs); k := done; LeaveCriticalSection(cs);
      if k < target then Sleep(1);
    until k >= target;
  end;
  DoneCriticalSection(cs);
  writeln('threads ', done);
end.
