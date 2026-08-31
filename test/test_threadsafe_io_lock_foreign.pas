program test_threadsafe_io_lock_foreign;

{$THREADSAFE ON}

{ --threadsafe I/O lock, from threads this program did NOT create.

  The lock's owner token is a thread id, and since
  feature-a-io-lock-owner-from-tls-not-gettid it is read from the thread's TLS
  block instead of a gettid syscall per statement. The thread pointer is
  INHERITED across clone, so a thread created by glibc pthread_create reads the
  block of whoever created it -- and taking that block's cached tid as its own
  makes the reentrancy check answer "the lock is already mine" for a lock this
  thread does not hold. The acquire is then skipped and mutual exclusion is
  silently gone.

  So this test asserts ATOMICITY, not agreement with the slot: four foreign
  threads each write 50 lines of 300 identical characters, and a `Writeln` is
  two write(2) calls (payload, newline). Without the lock two threads interleave
  those and produce a line that is not 300 of one character. The Makefile counts
  the WHOLE lines and demands exactly 200 of them plus the 'done' -- a torn run
  loses lines, and so does a crashed one, which a "no bad lines" test would score
  as a pass.

  This is the positive control for the TLS fast path: with the stack-bounds check
  removed from EmitIoLockStubs it was watched failing (mixed 600-character
  lines), and with it the four threads miss the fast path and pay gettid, which
  is the right way round. }

type
  PthreadT = QWord;
  PPthreadT = ^PthreadT;
  PInt = ^Integer;

function pthread_create(thread: PPthreadT; attr: Pointer; start_routine: Pointer; arg: Pointer): Integer; cdecl; external 'libpthread.so.0';
function pthread_join(thread: PthreadT; retval: Pointer): Integer; cdecl; external 'libpthread.so.0';

var
  idx: array[0..3] of Integer;
  tids: array[0..3] of PthreadT;
  i, res: Integer;

function ThreadFunc(arg: Pointer): Pointer; cdecl;
var
  k, j: Integer;
  c: Char;
  s: AnsiString;
begin
  k := PInt(arg)^;
  c := Chr(Ord('A') + k);
  s := '';
  for j := 1 to 300 do s := s + c;
  for j := 1 to 50 do
    Writeln(s);
  ThreadFunc := nil;
end;

begin
  for i := 0 to 3 do
  begin
    idx[i] := i;
    res := pthread_create(@tids[i], nil, @ThreadFunc, @idx[i]);
    if res <> 0 then
    begin
      Writeln('spawn failed');
      Halt(1);
    end;
  end;
  for i := 0 to 3 do
    pthread_join(tids[i], nil);
  Writeln('done');
end.
