program test_threadsafe_handler_alloc_no_lock_held;
{ THE OTHER SIDE OF THE HEAP LOCK'S ASYNC-REENTRY REFUSAL, and the regression it
  could have caused. test_threadsafe_heap_lock_deadlock_diag asserts that a
  handler allocating while the interrupted flow HELD the lock is named (212).
  This asserts the case that must keep WORKING: a handler allocating while the
  flow held NOTHING. That is the common case -- almost every real handler is in
  it -- and it has no other coverage.

  WHY IT NEEDS A ROW OF ITS OWN. Until 2026-09-16 a handler was handed the lock
  by the reentrant owner check: it runs on the thread it interrupted, so it
  presented the same tid and matched. Both cases took that path, so both
  "worked" and neither was distinguishable. Refusing the grant for handlers is
  what restores the 212 diagnosis, and it necessarily routes THIS case down the
  ordinary acquire instead -- a path a signal handler had not taken before. If
  that refusal is ever tightened into an unconditional verdict rather than a
  fall-through to the acquire, this program is what goes red, and it goes red as
  a FALSE 212 rather than as a hang.

  `hits` IS THE ASSERTION AND IT IS EXACT, not `> 0`. A directed tkill to self
  is delivered before the syscall returns, so N sends must produce exactly N
  handler entries; a count that merely moved would also be produced by a handler
  that ran once and wedged. Measured 10/10 identical at N=20000, magazine on and
  off. `spin-nonzero` is the inertness row: the main loop's own work must have
  happened, so a program that somehow skipped the loop entirely cannot report
  success from the handler alone.

  BOTH MAGAZINE SPELLINGS are run from the Makefile. With the per-thread
  magazine on, a handler's traffic can be served without reaching the lock at
  all -- so the magazine build does NOT exercise the acquire and would pass with
  the lock path completely broken. -dPXX_NO_HEAP_MAG is the one that tests
  anything here; the plain one is the control that the same source is correct
  either way.

  x86-64 only, like every thread test here: the stub is emitted machine code. }

const
  SYS_gettid = 186; SYS_tkill = 200;
  USR1 = 10;
  N = 20000;

var
  mainTid: Int64;
  hits, i, spin: Integer;
  r: Int64;

function Tid: Int64; begin Tid := __pxxrawsyscall(SYS_gettid); end;

procedure Hook;
var p: Pointer;
begin
  hits := hits + 1;
  GetMem(p, 96);
  FreeMem(p);
end;

begin
  mainTid := Tid; hits := 0; spin := 0;
  SetSignalHandler(USR1, @Hook);
  for i := 1 to N do
  begin
    { The handler runs inside this syscall's return, with the main flow holding
      no heap lock: it is between allocations, not inside one. }
    r := __pxxrawsyscall(SYS_tkill, mainTid, USR1);
    spin := spin + i;
  end;
  WriteLn('hits=', hits);
  WriteLn('spin-nonzero=', spin > 0);
  if (hits = N) and (spin > 0) then
    WriteLn('SIGALLOC OK')
  else
    WriteLn('SIGALLOC FAIL');
end.
