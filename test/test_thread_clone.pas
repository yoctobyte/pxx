program test_thread_clone;
{ M1 libc-free threading smoke test (x86-64). Spawns several real OS threads via
  the __pxxclone trampoline (clone(2)); each child runs in the SHARED address
  space (CLONE_VM) and writes its own result slot; the parent joins each by
  futex-waiting on its CLONE_CHILD_CLEARTID word. No libc, no libpthread — pure
  syscalls (mmap/clone/futex/exit).

  Verifies: every child ran (all slots written), join blocks until each child
  exits, and every returned tid is a real positive tid. }

const
  { thread clone flags: VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID }
  PXX_CLONE_THREAD = $350F00;
  SYS_mmap  = 9;
  SYS_futex = 202;
  FUTEX_WAIT = 0;
  PROT_RW   = 3;            { PROT_READ or PROT_WRITE }
  MAP_ANON_PRIV = $22;     { MAP_PRIVATE or MAP_ANONYMOUS }
  STK = 1024 * 1024;       { 1 MiB per child stack }
  NT  = 4;                 { number of threads }

var
  results: array[0..NT-1] of Integer;   { each child writes its own slot }
  tidword: array[0..NT-1] of Integer;   { per-thread CLONE_*_TID futex word }

procedure ThreadEntry(arg: Pointer);
var
  k, spin: Int64;
begin
  k := Int64(arg);
  { burn some cycles so the threads genuinely overlap rather than run serially }
  spin := 0;
  while spin < 2000000 do spin := spin + 1;
  results[k] := 1000 + k;
end;

var
  stackBase, tid: Int64;
  i, t: Integer;
  ignore: Int64;
  okCount: Integer;
begin
  for i := 0 to NT - 1 do
  begin
    results[i] := 0;
    tidword[i] := 0;
    stackBase := __pxxrawsyscall(SYS_mmap, 0, STK, PROT_RW, MAP_ANON_PRIV, -1, 0);
    if stackBase < 0 then begin writeln('mmap FAIL ', stackBase); Halt(1); end;
    tid := __pxxclone(PXX_CLONE_THREAD, stackBase + STK, @ThreadEntry,
                      Pointer(i), @tidword[i]);
    if tid <= 0 then begin writeln('clone FAIL ', tid); Halt(1); end;
  end;

  { join each: futex-wait until the kernel clears that thread's tidword on exit }
  for i := 0 to NT - 1 do
    while True do
    begin
      t := tidword[i];
      if t = 0 then Break;
      ignore := __pxxrawsyscall(SYS_futex, Int64(@tidword[i]), FUTEX_WAIT, t, 0, 0, 0);
    end;

  okCount := 0;
  for i := 0 to NT - 1 do
  begin
    writeln('thread ', i, ' -> ', results[i]);
    if results[i] = 1000 + i then okCount := okCount + 1;
  end;

  writeln('total ok ', okCount, ' / ', NT);
  if okCount = NT then writeln('THREADS OK') else writeln('THREADS FAIL');
end.
