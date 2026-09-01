program test_heap_magazine_foreign_thread;

{ THE FOREIGN THREAD IS THE WHOLE POINT. These workers come from libc's
  pthread_create, not from __pxxclone, so none of them runs the clone stub in
  thread_emit.inc that carves and installs a per-thread TLS block -- each one
  simply INHERITS the main thread's gs. Measured 2026-09-01 with gdb on
  test/test_multithreading.pas: gs_base = 0x411f98, which is BSS_TLS_MAIN, on
  all five threads at once.

  The heap magazine lives in that block and used to guard itself with a plain
  load-test-store, on the premise that gs named a block this thread owned and
  the only other entrant could be a signal handler. Six threads sharing one
  magazine with no mutual exclusion tore the head/count pair, and the fault
  surfaced far away -- inside PXXAlloc's global bin pop, reading a head of 8,
  a magazine COUNT sitting where a pointer belongs. The guard is now an
  `xchg r64, m64`.

  WHY THIS SHAPE AND NOT test_multithreading's. That test reproduces the crash
  about 15 runs in 100, which is a coin toss in a gate rather than a guard.
  This one raises the collision rate on purpose: six threads instead of four,
  every allocation inside the magazine's size range (8..512), and no usleep
  between them, so the threads stay inside the fast path rather than taking
  turns. Measured against a compiler built with the plain-store guard: 20 of 20
  runs died. With the xchg guard: 0 of 20, and 0 of 210 for the pair of these
  and test_multithreading together.

  A rate is not a proof, so read the row honestly: it cannot show the race is
  IMPOSSIBLE, only that a shape which failed every single time now fails none.
  Anyone touching EmitHeapMagAllocTry, EmitHeapMagFreeTry or the TLS layout
  should re-measure the 20-of-20 rather than trusting this line to stay red.

  Sizes stay <= 512 (HEAP_MAG_MAX) and >= 8 deliberately: outside that range
  both fast paths miss and fall into the locked allocator, which was never the
  bug and would make the test pass for the wrong reason. }

type
  PthreadT = QWord;
  PPthreadT = ^PthreadT;

const
  NTHREAD = 6;
  NITER   = 1500;

function pthread_create(thread: PPthreadT; attr: Pointer; start_routine: Pointer; arg: Pointer): Integer; cdecl; external 'libpthread.so.0';
function pthread_join(thread: PthreadT; retval: Pointer): Integer; cdecl; external 'libpthread.so.0';

var
  tids: array[0..NTHREAD - 1] of PthreadT;
  bad: Integer;

function Worker(arg: Pointer): Pointer; cdecl;
var
  p: ^Int64;
  i, sz: Integer;
begin
  for i := 1 to NITER do
  begin
    sz := 8 * (i mod 64 + 1);          { 8..512, one per magazine class }
    p := GetMem(sz);
    if p = nil then bad := bad + 1
    else
    begin
      { A block handed back by either path must be zeroed -- the magazine's own
        rep stosb is what guarantees that on a hit, so reading it is a check of
        the fast path and not just of the pointer. }
      if p^ <> 0 then bad := bad + 1;
      p^ := i;
      if p^ <> i then bad := bad + 1;
      FreeMem(p);
    end;
  end;
  Worker := nil;
end;

var
  k: Integer;
begin
  bad := 0;
  for k := 0 to NTHREAD - 1 do
    if pthread_create(@tids[k], nil, @Worker, nil) <> 0 then
    begin
      WriteLn('MAGFOREIGN FAILED: pthread_create');
      Halt(1);
    end;
  for k := 0 to NTHREAD - 1 do
    pthread_join(tids[k], nil);
  if bad <> 0 then
  begin
    WriteLn('MAGFOREIGN FAILED bad=', bad);
    Halt(1);
  end;
  WriteLn('MAGFOREIGN OK ', NTHREAD * NITER);
end.
