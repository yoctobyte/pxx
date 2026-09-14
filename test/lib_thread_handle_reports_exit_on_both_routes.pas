program lib_thread_handle_reports_exit_on_both_routes;
{ A finished thread must REPORT itself finished, on whichever route created it.

  The handle's TidWord is the one word every "has it stopped?" consumer reads --
  Thread.is_alive, the timed arm of Thread.join, TThread.WaitFor via
  palthreadobj. On the clone route the KERNEL maintains it: CLONE_PARENT_SETTID
  fills it before the child runs and CLONE_CHILD_CLEARTID zeroes it and
  futex-wakes as the thread's last act. glibc's thread has neither flag, so on
  the pthread route the trampoline has to do both by hand, and between
  2026-09-14's route-1 landing and its fix it did only the first.

  WHY THIS FILE HARD-IMPORTS getpid, WHICH IT OTHERWISE HAS NO USE FOR: a
  program whose only libc imports are WEAK collapses to a static link
  (DropWeakOnlyImports), pthread_create then reads nil, and PalThreadCreate
  takes the CLONE route -- where the kernel does all of this correctly and the
  bug is unreachable. A test without a hard libc import passes on a broken
  pthread route by never using it. One unused external is what puts a
  DT_NEEDED on libc.so.6 and makes the weak import resolve.

  POSITIVE CONTROL, measured 2026-09-14: with the `h^.TidWord := 0` +
  FutexWake pair removed from PxxPthreadStart, the ROUTE row still says
  pthread, TIDWORD says 1 (non-zero) and the JOIN row says SLOW -- the timed
  join burns its full 2 s and the thread is never reaped, so glibc keeps its
  stack and TLS for the life of the process. All three rows move.

  It asserts RELATIONS, never the tid value: the tid is a different number on
  every run and on every host. }
uses palthread, palfutex, sysutils;

{ Not called. Present so the binary links libc dynamically -- see above. }
function c_getpid: Integer; cdecl; external 'libc.so.6' name 'getpid';

var
  h: TThreadHandle;
  t: Integer;
  left, slice: Int64;
  ig: Integer;
  t0, t1: TDateTime;
  elapsedMs: Int64;
  usedPthread: Boolean;
  ok: Boolean;

procedure Body(arg: Pointer);
begin
end;

begin
  if c_getpid <= 0 then
  begin
    WriteLn('getpid failed -- the libc link this test depends on is not there');
    Halt(1);
  end;
  if PalThreadCreate(h, @Body, nil, 0) <> 0 then
  begin
    WriteLn('PalThreadCreate failed');
    Halt(1);
  end;
  usedPthread := h.PthreadId <> 0;
{$ifdef CPUX86_64}
  { AIM THE GUARD. On x86-64 with libc linked the pthread route is the whole
    point of this file; if we silently got the clone route the three rows below
    would pass while testing nothing. Fail loudly instead. }
  if not usedPthread then
  begin
    WriteLn('ROUTE pthread-expected-but-got-clone');
    Halt(1);
  end;
{$endif}
  if usedPthread then WriteLn('ROUTE pthread') else WriteLn('ROUTE clone');
  ok := True;

  { Let the body -- which is empty -- run to completion. }
  Sleep(400);

  { 1. The handle reports the thread as stopped. }
  if h.TidWord = 0 then WriteLn('TIDWORD 0')
  else begin WriteLn('TIDWORD 1'); ok := False; end;

  { 2. A TIMED join returns promptly rather than burning its timeout. This is
       mimic_threading.Thread.join's timed arm, which is what a Python
       `t.join(timeout=2.0)` runs, and what lekkerzeilen's shutdown calls per
       thread. Threshold is deliberately loose: the claim is "does not wait for
       the timeout", not a latency figure. }
  t0 := Now;
  left := 2 * 1000 * 1000 * 1000;
  while left > 0 do
  begin
    t := h.TidWord;
    if t = 0 then Break;
    slice := left;
    if slice > 50 * 1000 * 1000 then slice := 50 * 1000 * 1000;
    ig := PalFutexWaitTimeout(@h.TidWord, t, slice);
    left := left - slice;
  end;
  t1 := Now;
  elapsedMs := Round((t1 - t0) * 86400.0 * 1000.0);
  if elapsedMs < 1000 then WriteLn('JOIN PROMPT')
  else begin WriteLn('JOIN SLOW'); ok := False; end;

  { 3. And the reap is therefore reachable. PalThreadJoin is gated on exactly
       this condition in every caller; when it is False the pthread_join never
       runs and glibc holds the thread's stack and TLS forever. }
  if h.TidWord = 0 then
  begin
    PalThreadJoin(h);
    WriteLn('REAPED');
  end
  else
  begin
    WriteLn('NOT-REAPED');
    ok := False;
  end;

  { THE VERDICT IS THE LAST LINE AND IT MUST BE ABLE TO SAY NO. This printed
    'THREADEXIT OK' unconditionally for its first half-hour, under three rows
    that were correctly reporting the defect -- so a Makefile row asserting the
    tail passed on the broken RTL while the evidence scrolled past above it.
    That is the guard-that-cannot-fail, built by the person who had just
    measured the bug. }
  if ok then WriteLn('THREADEXIT OK') else WriteLn('THREADEXIT FAIL');
end.
