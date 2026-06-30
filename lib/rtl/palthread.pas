unit palthread;
{ M1 libc-free thread PAL (meta-multithreading). Wraps the compiler's __pxxclone
  trampoline plus raw mmap/futex/munmap syscalls into a small, FPC-flavoured
  thread-primitive API. No libc, no libpthread — pure Linux syscalls.

  This is the single low-level layer the rest of the threading stack builds on:
  the futex sync primitives (M2), native TThread (M3) and the C pthread shim (M4)
  all sit on PalThreadCreate/Join + PalFutex*. Threading is opt-in: nothing here
  runs unless a program `uses palthread`, and the single-threaded self-host build
  never pulls it in.

  x86-64 first. Other targets compile-error at the __pxxclone call site until
  their trampoline lands (the syscall-number tables below are also x86-64 only). }

interface

type
  { A thread body: receives the opaque argument passed to PalThreadCreate. Runs on
    the cloned thread; returning from it exits the thread. }
  TThreadEntry = procedure(arg: Pointer);

  PThreadHandle = ^TThreadHandle;
  { Owns one spawned thread. TidWord doubles as the join futex: the kernel sets it
    to the child tid at clone time (CLONE_PARENT_SETTID) and clears it + futex-wakes
    on exit (CLONE_CHILD_CLEARTID). Its address must stay stable from create to
    join, so keep the handle alive (caller stack / heap) across the thread's life. }
  TThreadHandle = record
    Tid:       Int64;     { child tid (kernel thread id), > 0 on success }
    TidWord:   Integer;   { CLONE_*_TID futex word — join waits on this }
    StackBase: Int64;     { mmap'd child-stack base (freed by Join) }
    StackSize: Int64;
  end;

const
  PAL_DEFAULT_STACK = 1024 * 1024;   { 1 MiB default child stack }

{ Spawn a thread running entry(arg) on a fresh mmap'd stack. stackSize <= 0 picks
  PAL_DEFAULT_STACK. Fills h and returns 0 on success, negative on failure. }
function PalThreadCreate(var h: TThreadHandle; entry: TThreadEntry; arg: Pointer;
                         stackSize: Int64): Integer;

{ Block until the thread exits, then release its stack. Idempotent once joined. }
procedure PalThreadJoin(var h: TThreadHandle);

{ Sleep while addr^ still equals expected (FUTEX_WAIT). Returns the raw syscall
  result. Used to build mutexes/events on top. }
function PalFutexWait(addr: Pointer; expected: Integer): Integer;

{ Wake up to count waiters blocked on addr (FUTEX_WAKE). count = high value wakes
  all. Returns the number woken (raw syscall result). }
function PalFutexWake(addr: Pointer; count: Integer): Integer;

{ Kernel thread id of the caller (gettid). }
function PalThreadSelf: Int64;

implementation

const
  { thread clone flags: VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID.
    PARENT_SETTID|CHILD_CLEARTID make TidWord a race-free join handshake. }
  PXX_CLONE_THREAD = $350F00;

  FUTEX_WAIT = 0;
  FUTEX_WAKE = 1;

  PROT_RW       = 3;        { PROT_READ or PROT_WRITE }
  MAP_ANON_PRIV = $22;      { MAP_PRIVATE or MAP_ANONYMOUS }

{$ifdef CPUX86_64}
  SYS_mmap   = 9;
  SYS_munmap = 11;
  SYS_futex  = 202;
  SYS_gettid = 186;
{$else}
  { Non-x86-64 trips the __pxxclone compile-error before these matter; define
    placeholders so the unit still parses. }
  SYS_mmap   = -1;
  SYS_munmap = -1;
  SYS_futex  = -1;
  SYS_gettid = -1;
{$endif}

function PalFutexWait(addr: Pointer; expected: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAIT, expected, 0, 0, 0));
end;

function PalFutexWake(addr: Pointer; count: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAKE, count, 0, 0, 0));
end;

function PalThreadSelf: Int64;
begin
  Result := __pxxrawsyscall(SYS_gettid, 0, 0, 0, 0, 0, 0);
end;

function PalThreadCreate(var h: TThreadHandle; entry: TThreadEntry; arg: Pointer;
                         stackSize: Int64): Integer;
var
  ignore: Int64;
begin
  if stackSize <= 0 then stackSize := PAL_DEFAULT_STACK;
  h.Tid := 0;
  h.TidWord := 0;
  h.StackSize := stackSize;
  h.StackBase := __pxxrawsyscall(SYS_mmap, 0, stackSize, PROT_RW, MAP_ANON_PRIV, -1, 0);
  if h.StackBase < 0 then
  begin
    h.StackBase := 0;
    Result := -1;
    Exit;
  end;
  { Child stack grows down from the high end; must be 16-byte aligned (mmap is
    page-aligned and stackSize is a multiple of 16, so the top is too). }
  h.Tid := __pxxclone(PXX_CLONE_THREAD, h.StackBase + stackSize,
                      entry, arg, @h.TidWord);
  if h.Tid <= 0 then
  begin
    { clone failed: reclaim the stack, report failure. }
    ignore := __pxxrawsyscall(SYS_munmap, h.StackBase, h.StackSize, 0, 0, 0, 0);
    h.StackBase := 0;
    Result := -1;
    Exit;
  end;
  Result := 0;
end;

procedure PalThreadJoin(var h: TThreadHandle);
var
  t: Integer;
  ignore: Int64;
begin
  { Wait until the kernel clears TidWord on child exit. CHILD_CLEARTID clears it
    as the thread's final act (stack no longer in kernel use), so freeing the
    stack afterwards is safe. }
  while True do
  begin
    t := h.TidWord;
    if t = 0 then Break;
    PalFutexWait(@h.TidWord, t);
  end;
  if h.StackBase > 0 then
  begin
    ignore := __pxxrawsyscall(SYS_munmap, h.StackBase, h.StackSize, 0, 0, 0, 0);
    h.StackBase := 0;
  end;
end;

end.
