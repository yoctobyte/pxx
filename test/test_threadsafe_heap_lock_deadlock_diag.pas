program test_threadsafe_heap_lock_deadlock_diag;
{ The --threadsafe heap lock must NAME a deadlock instead of hanging forever
  (bug-a-the-threadsafe-allocator-is-not-async-signal-safe, option 3).

  It does not fix the deadlock -- a signal handler that allocates while the
  interrupted flow holds the global heap lock still cannot proceed -- it turns
  the outcome from "20s timeout, no output at all" into a message naming the
  cause and exit(212). That is the whole claim, so the test asserts the message
  and the code, not merely that the program stopped.

  TWO PHASES IN ONE BINARY, and the first is the one that makes the second
  readable. The diagnosis is a counter, and a counter that fires is worthless
  without a run that must not fire it: phase 1 is twelve threads doing nothing
  but GetMem/FreeMem, the heaviest LEGITIMATE contention this lock can see, and
  it must reach the end. Measured while sizing HEAP_LOCK_SPIN_LIMIT, phase 1
  DOES falsely diagnose at a limit of 2^18 -- so it is a control that can fail,
  not a decorative one.

  `-dPXX_NO_HEAP_MAG` is required and is not a convenience. With the per-thread
  magazine in place a handler whose traffic fits it never reaches the lock at
  all; the retaining ring below was written to miss the magazine and, measured,
  still survived 880359 handler hits with the magazine on. Compiling it out is
  what puts every allocation on the lock, which is the code path under test.

  x86-64 only, like every thread test here: the stub is emitted machine code. }

const
  SYS_gettid = 186; SYS_tkill = 200;
  USR1 = 10;
  RING = 64;
  WORKERS = 12;
  WORK_ROUNDS = 200000;
  MAIN_ROUNDS = 2000000;

var
  mainTid: Int64;
  ring: array[0..RING - 1] of Pointer;
  ringN, hits, go, doneN: Integer;
  ids: array[0..WORKERS - 1] of TThreadID;
  sigId: TThreadID;

function Tid: Int64; begin Tid := __pxxrawsyscall(SYS_gettid); end;

{ The handler RETAINS: it keeps its blocks and frees the batch only when the
  ring wraps. A handler that allocates and immediately frees hands the block
  straight back and can be served without ever blocking -- that shape is why
  the first version of this measurement came back green. }
procedure Hook;
var i: Integer; p: Pointer;
begin
  hits := hits + 1;
  GetMem(p, 96);
  ring[ringN] := p;
  ringN := ringN + 1;
  if ringN >= RING then
  begin
    for i := 0 to RING - 1 do FreeMem(ring[i]);
    ringN := 0;
  end;
end;

function Contend(par: Pointer): PtrInt;
var i: Integer; p: Pointer;
begin
  while go = 0 do ;
  for i := 1 to WORK_ROUNDS do
  begin
    GetMem(p, 64);
    FreeMem(p);
  end;
  doneN := doneN + 1;
  Contend := 0;
end;

function Hammer(par: Pointer): PtrInt;
var i: Integer; r: Int64;
begin
  for i := 1 to MAIN_ROUNDS do
    r := __pxxrawsyscall(SYS_tkill, mainTid, USR1);
  Hammer := 0;
end;

var i: Integer; p: Pointer;
begin
  mainTid := Tid;
  ringN := 0; hits := 0; go := 0; doneN := 0;

  { ---- phase 1: the CONTROL. Heavy legitimate contention must NOT diagnose. }
  for i := 0 to WORKERS - 1 do ids[i] := BeginThread(@Contend, nil);
  go := 1;
  for i := 0 to WORKERS - 1 do WaitForThreadTerminate(ids[i], 0);
  WriteLn('contention-workers-finished=', doneN);
  Flush(Output);

  { ---- phase 2: the deadlock. Never returns; the stub writes to stderr and
    exit_group(212)s, so nothing below the loop is reachable and the harness
    asserts the exit code as well as the message. }
  SetSignalHandler(USR1, @Hook);
  sigId := BeginThread(@Hammer, nil);
  for i := 1 to MAIN_ROUNDS do
  begin
    GetMem(p, 64);
    FreeMem(p);
  end;
  WriteLn('NOT REACHED: the handler never collided with the lock');
end.
