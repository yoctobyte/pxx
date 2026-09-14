{ SPDX-License-Identifier: Zlib }
unit palthread;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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

uses palfutex;

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
    { RACE CONTRACT (see devdocs/dev/threading.md "Tid identity"): Tid is stored
      by the PARENT after __pxxclone returns, but the child may already be
      running — so Tid is safe for parent-side reads (program order) and for any
      thread that obtained the handle after PalThreadCreate returned, but NOT
      for the child's own early reads (it can observe a stale 0 before Execute).
      A child that needs its identity in the handle must self-write it first
      (PalThreadSelf; same value, so the duplicate store is benign — see
      ThreadObjLauncher in palthreadobj.pas), or use TidWord, which the KERNEL
      fills before the child runs (CLONE_PARENT_SETTID) — but TidWord is
      cleared again at thread exit (CLONE_CHILD_CLEARTID), so it is only valid
      while the thread lives. }
    Tid:       Int64;     { child tid (kernel thread id), > 0 on success }
    TidWord:   Integer;   { CLONE_*_TID futex word — join waits on this }
    StackBase: Int64;     { mmap'd child-stack base (freed by Join); 0 on the pthread route }
    StackSize: Int64;
    { ---- the pthread route (see PalThreadCreate) ---- }
    { pthread_t of the child, 0 when this thread was made by __pxxclone. It is
      the ROUTE DISCRIMINATOR as well as the id: Join must call pthread_join for
      a thread glibc created, because CLONE_CHILD_CLEARTID is what makes the
      futex handshake work and glibc's thread never had that flag. }
    PthreadId: Int64;
    { Staged for the trampoline, so the pthread route needs no allocation at
      all: the handle is already caller-owned and stable from create to join,
      which is exactly the lifetime a start-routine argument needs. }
    EntryFn:   Pointer;
    EntryArg:  Pointer;
  end;

const
  PAL_DEFAULT_STACK = 1024 * 1024;   { 1 MiB default child stack }
  { What the clone stub carves off the top before the child's first instruction
    -- a 4224-byte TLS block, a 32768-byte signal alt stack and a 256-byte
    hidden-destination scratch for an entry that returns an aggregate -- plus a
    64KB working floor. Stated as one number here rather than derived from the
    compiler's constants because the RTL cannot see them; if either grows, this
    is the second copy and the stub is the first.

    The block was 1152 bytes until `threadvar` landed. It is now 1152 bytes of
    compiler-owned slot map plus TLS_USER_BYTES (3072) of source-declared
    per-thread variables -- a FIXED cap, so this number does not move with the
    program. Raise both together or not at all. }
  PAL_MIN_STACK = 128 * 1024;

{ Spawn a thread running entry(arg) on a fresh mmap'd stack. stackSize <= 0 picks
  PAL_DEFAULT_STACK. Fills h and returns 0 on success, negative on failure. }
function PalThreadCreate(var h: TThreadHandle; entry: TThreadEntry; arg: Pointer;
                         stackSize: Int64): Integer;

{ Block until the thread exits, then release its stack. Idempotent once joined. }
procedure PalThreadJoin(var h: TThreadHandle);

{ PalFutexWait / PalFutexWake / PalFutexWaitTimeout moved to `palfutex`, which
  depends on nothing: waiting on a word must not inherit __pxxclone's
  --threadsafe gate. `uses` is not transitive, so a caller that wants them needs
  its own `uses palfutex` — this unit re-exports nothing. }

{ Kernel thread id of the caller (gettid). }
function PalThreadSelf: Int64;

{ End the CALLING thread now, without unwinding (SYS_exit, NOT exit_group — the
  process and its other threads keep running). The kernel clears the handle's
  TidWord and futex-wakes any joiner, so a PalThreadJoin on this thread returns
  normally. Never returns. Called on the main thread it ends that thread only,
  which on Linux leaves the process alive with no main — so don't. }
procedure PalThreadExit;

implementation

const
  { thread clone flags: VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|PARENT_SETTID|CHILD_CLEARTID.
    PARENT_SETTID|CHILD_CLEARTID make TidWord a race-free join handshake. }
  PXX_CLONE_THREAD = $350F00;

  PROT_NONE     = 0;        { guard page: no access }
  PROT_RW       = 3;        { PROT_READ or PROT_WRITE }
  MAP_ANON_PRIV = $22;      { MAP_PRIVATE or MAP_ANONYMOUS }
  PAGE_SIZE     = 4096;

{$ifdef CPUX86_64}
  SYS_mmap     = 9;
  SYS_munmap   = 11;
  SYS_mprotect = 10;
  SYS_gettid   = 186;
  SYS_exit     = 60;
  { The pthread route's trampoline (PxxPthreadStart) installs pxx's own thread
    block and alt stack the way the clone stub's child leg does. They are
    x86-64 syscall numbers, so they belong in the x86-64 arm with the five
    above; no other target reaches the pthread route.

    A NOTE FOR ANYONE BISECTING THIS FILE AGAIN: adding these three lines used
    to make test_a_threadvar_is_per_thread segfault, and the shape of that --
    a crash that moves when you add an unrelated declaration -- says symbol
    NUMBERING, never the declaration. It was
    bug-a-a-symbol-a-threadvar-program-never-declared-is-lowered-as-a-threadvar:
    four of the five Alloc* paths left SymTlsOffset at SetLength's zero, which
    RewriteThreadVarRefs reads as a threadvar at gs:+0. Fixed in the compiler;
    nothing here is a workaround. }
  SYS_arch_prctl  = 158;
  SYS_sigaltstack = 131;
  ARCH_SET_GS     = $1001;
{$else}
{$ifdef CPUI386}
  { i386 int 0x80 numbers. SYS_mmap is mmap2 (192): its last arg is an offset
    in PAGES rather than bytes — we always pass 0, so the call shape is
    identical to x86-64's mmap. }
  SYS_mmap     = 192;
  SYS_munmap   = 91;
  SYS_mprotect = 125;
  SYS_gettid   = 224;
  SYS_exit     = 1;
{$else}
{$ifdef CPUAARCH64}
  { aarch64 uses the asm-generic syscall table. Real mmap (222), byte offset. }
  SYS_mmap     = 222;
  SYS_munmap   = 215;
  SYS_mprotect = 226;
  SYS_gettid   = 178;
  SYS_exit     = 93;
{$else}
{$ifdef CPUARM}
  { arm32 EABI. mmap2 (192, page offset — we pass 0). These five happen to match
    the i386 int-0x80 numbers. }
  SYS_mmap     = 192;
  SYS_munmap   = 91;
  SYS_mprotect = 125;
  SYS_gettid   = 224;
  SYS_exit     = 1;
{$else}
  { Other targets trip the __pxxclone compile-error before these matter; define
    placeholders so the unit still parses. }
  SYS_mmap     = -1;
  SYS_munmap   = -1;
  SYS_mprotect = -1;
  SYS_gettid   = -1;
  SYS_exit     = -1;
{$endif}
{$endif}
{$endif}
{$endif}

function PalThreadSelf: Int64;
begin
  Result := __pxxrawsyscall(SYS_gettid, 0, 0, 0, 0, 0, 0);
end;

{ ---------------------------------------------------------------------------
  THE pthread ROUTE, and why it exists.

  A thread made by __pxxclone runs on the PARENT's `fs` base, because the clone
  flags omit CLONE_SETTLS -- deliberately, since pxx keeps its own thread block
  on `gs` and installs it from the child itself. `fs` is glibc's thread pointer,
  and glibc's malloc keeps its per-thread state there and takes NO LOCK on it,
  because it is per-thread by construction. So the moment a pxx-created thread
  and any other thread both allocate through a C library, they operate one
  malloc state concurrently and corrupt glibc's heap. Measured 5/5 on a 60-line
  repro; the same churn single-threaded is clean, and the same churn with the
  worker made by pthread_create is clean.
  bug-a-a-pxx-created-thread-shares-glibc-s-thread-pointer-so-two-threads-share-one-malloc-state

  Synthesising a glibc-compatible TCB ourselves was measured and rejected: a
  zeroed static TLS area segfaults inside malloc (thread-locals are initialised
  from each module's TLS template, so producing one correctly is
  `_dl_allocate_tls` reimplemented) and a copied one carries the parent's malloc
  state, reproducing the bug exactly. That work is what pthread_create exists to
  do.

  WHAT MADE THIS A FORK UNTIL NOW, and what dissolved it: `external 'libc.so.6'`
  here would put libc in EVERY pxx program's DT_NEEDED, including the static,
  libc-free ones that are a large part of what pxx is for. `weakexternal` does
  not -- a library reached only by weak imports emits no DT_NEEDED at all, so
  these resolve exactly when the program already links libc for some other
  reason (SDL, sqlite) and are nil otherwise. A program with no C library in it
  has no second malloc state to share, so the clone path is entirely correct
  there. Neither world pays for the other.

  x86-64 ONLY, and that is a real limit rather than a tidy-up left for later:
  the trampoline has to install pxx's own block on `gs`, and arch_prctl is the
  only mechanism this runtime has for that. The other targets keep the clone
  path and keep the bug, tracked as
  bug-a-a-cloned-thread-still-inherits-the-parents-fs-base-on-every-target-but-x86-64.
  The compiler's whole-program warning still fires for them and is now SILENT on
  x86-64, because its own condition -- links a shared library AND creates pxx
  threads -- is exactly when these two imports resolve.
  --------------------------------------------------------------------- }

function c_pthread_create(th: Pointer; attr: Pointer; start: Pointer; arg: Pointer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'pthread_create';
function c_pthread_join(th: Int64; retval: Pointer): Integer; cdecl;
  weakexternal 'libc.so.6' name 'pthread_join';

function PthreadRouteAvailable: Boolean;
{ Both halves, not one: a program that could create but not join would leak a
  thread on every Join and never report it. }
begin
{$ifdef CPUX86_64}
  Result := (@c_pthread_create <> nil) and (@c_pthread_join <> nil);
{$else}
  Result := False;
{$endif}
end;

{$ifdef CPUX86_64}
function PxxPthreadStart(a: Pointer): Pointer; cdecl;
{ The start routine glibc calls. Does for a pthread-made thread exactly what the
  clone stub's child leg does for a cloned one -- install pxx's `gs` block and
  register a per-thread signal alt stack -- then runs the entry.

  ORDER IS THE WHOLE OF THE CORRECTNESS ARGUMENT HERE. Everything before the
  arch_prctl runs on the PARENT's `gs`, so it must touch nothing that reaches
  through it: no allocation, no managed string, no threadvar. Raw syscalls and
  pointer stores only. (It would not in fact corrupt anything today -- the
  allocator's magazine guard was made atomic in 2026-09-01 precisely because
  foreign pthread-made threads inherit the creator's gs -- but relying on that
  would make this routine's correctness depend on a decision made elsewhere for
  another reason.)

  The block is ONE anonymous mmap: TLS block first (its slot 0 must hold its own
  address -- the convention __pxxTlsBase reads through), alt stack above it. mmap
  hands back zeroed pages, and an all-zero slot map is already the correct
  initial state: every `threadvar` starts at 0, as the language requires, and an
  all-zero magazine IS "every size class empty". }
var
  h: PThreadHandle;
  blk, ignore, tlsBytes, altBytes: Int64;
  ss: array[0..2] of Int64;
  fn: TThreadEntry;
begin
  h := PThreadHandle(a);
  { Read from the COMPILER rather than restated. PAL_MIN_STACK above already
    restates these two and says in its own comment that it is the second copy;
    a third copy of a number that has moved once already (TLS_BLOCK_SIZE grew
    when `threadvar` landed) is silent corruption waiting for the next change,
    because too small a block means gs-relative slots write past the mapping.
    LOCALS AND NOT CONSTANTS only because the const-expression evaluator is a
    different path from ParseFactorCore and does not see these builtins; they
    fold to literals here, so it costs two register loads per thread. }
  tlsBytes := __pxxTlsBlockSize;
  altBytes := __pxxSigAltStackSize;
  blk := __pxxrawsyscall(SYS_mmap, 0, tlsBytes + altBytes,
                         PROT_RW, MAP_ANON_PRIV, -1, 0);
  if blk > 0 then
  begin
    PInt64(blk)^ := blk;                       { slot 0 = the block's own address }
    ignore := __pxxrawsyscall(SYS_arch_prctl, ARCH_SET_GS, blk, 0, 0, 0, 0);
    ss[0] := blk + tlsBytes;                   { ss_sp }
    ss[1] := 0;                                { ss_flags }
    ss[2] := altBytes;                         { ss_size }
    ignore := __pxxrawsyscall(SYS_sigaltstack, Int64(@ss[0]), 0, 0, 0, 0, 0);
  end;

  { Publish identity, THEN wake the parent. PalThreadCreate blocks on this
    rather than returning Tid = 0: every existing consumer of the handle reads
    .Tid straight after create (palthreadobj's registry lookup, its self-join
    guard, TThread.ThreadID), so a route that could not fill it in would be a
    different contract wearing the same record. The wait is bounded by the
    child reaching its first instruction, which glibc has already scheduled. }
  h^.Tid := PalThreadSelf;
  h^.TidWord := Integer(h^.Tid);
  ignore := PalFutexWake(@h^.TidWord, 1);

  fn := TThreadEntry(h^.EntryFn);
  fn(h^.EntryArg);

  if blk > 0 then
    ignore := __pxxrawsyscall(SYS_munmap, blk, tlsBytes + altBytes, 0, 0, 0, 0);
  Result := nil;
end;
{$endif}

procedure PalThreadExit;
var ignore: Int64;
begin
  { SYS_exit (this thread) rather than exit_group (the process). The clone flags
    include CLONE_CHILD_CLEARTID, so the kernel zeroes TidWord and futex-wakes
    the joiner as part of this call — which is what makes an early exit
    indistinguishable from returning off the end of the thread body. }
  ignore := __pxxrawsyscall(SYS_exit, 0, 0, 0, 0, 0, 0);
end;

function PalThreadCreate(var h: TThreadHandle; entry: TThreadEntry; arg: Pointer;
                         stackSize: Int64): Integer;
var
  ignore: Int64;
begin
  if stackSize <= 0 then stackSize := PAL_DEFAULT_STACK;
  { A FLOOR, because the clone stub carves off the TOP before the thread runs:
    a TLS block (4224 bytes: the slot map plus the `threadvar` area) and, since a cloned thread got its own signal alt
    stack, SIG_ALTSTACK_SIZE (32768) above it. A caller asking for less than
    that is not getting a small stack, it is getting a stub writing past the
    end of the mapping -- and the failure would land in another thread's
    storage rather than on this one's guard page, so it would not look like a
    stack problem at all. Raised silently rather than refused: a thread that
    runs is what the caller asked for, the extra pages are one mmap, and
    PalThreadCreate has no channel for "your request was adjusted".
    NECESSITY NOT DEMONSTRATED BY A CALLER: every call site in the tree passes
    0, i.e. the default, so nothing exercises this today and no measurement
    shows a caller hitting it. It is here because the STUB's requirement is new
    and unstated anywhere the caller can see, not because a bug was found. }
  if stackSize < PAL_MIN_STACK then stackSize := PAL_MIN_STACK;
  h.Tid := 0;
  h.PthreadId := 0;
  h.EntryFn := nil;
  h.EntryArg := nil;

{$ifdef CPUX86_64}
  { THE pthread ROUTE, taken exactly when the program already links libc. See
    the block comment above PxxPthreadStart for why it exists and why the weak
    import is what makes taking it free for everyone else. }
  if PthreadRouteAvailable then
  begin
    h.TidWord  := 0;
    { Pointer(entry), NOT Pointer(@entry): `entry` is a procedural PARAMETER, so
      `@` yields the address of the parameter slot on this stack frame -- which
      is a live pointer that survives long enough to be called, and then is not
      the routine. The clone path passes `entry` straight through for the same
      reason. }
    h.EntryFn  := Pointer(entry);
    h.EntryArg := arg;
    { No stack mmap: glibc allocates, guards and frees the child's stack, and
      the TLS/alt-stack regions the clone stub carves off the top are mmap'd by
      the trampoline instead. So StackBase stays 0 and Join frees nothing --
      which is also what makes the Join dispatch safe to write as an early Exit. }
    h.StackBase := 0;
    h.StackSize := 0;
    if c_pthread_create(@h.PthreadId, nil, Pointer(@PxxPthreadStart), @h) <> 0 then
    begin
      h.PthreadId := 0;
      Result := -1;
      Exit;
    end;
    { Block until the child has published its tid. Not a spin: PalFutexWait
      returns at once if the word already moved, so the common case is one
      syscall that does not sleep. See the trampoline for why Tid must be
      filled in before this returns rather than left to the caller. }
    while h.TidWord = 0 do
      ignore := PalFutexWait(@h.TidWord, 0);
    h.Tid := h.TidWord;
    Result := 0;
    Exit;
  end;
{$endif}
  h.TidWord := 0;
  { One extra page at the LOW end becomes a PROT_NONE guard: running the stack
    past its bottom faults immediately instead of silently scribbling into
    whatever mmap happens to sit below. StackSize records the full mapping so
    Join's munmap releases the guard too. }
  h.StackSize := stackSize + PAGE_SIZE;
  h.StackBase := __pxxrawsyscall(SYS_mmap, 0, h.StackSize, PROT_RW, MAP_ANON_PRIV, -1, 0);
  if h.StackBase < 0 then
  begin
    h.StackBase := 0;
    Result := -1;
    Exit;
  end;
  ignore := __pxxrawsyscall(SYS_mprotect, h.StackBase, PAGE_SIZE, PROT_NONE, 0, 0, 0);
  { Child stack grows down from the high end; must be 16-byte aligned (mmap is
    page-aligned and stackSize is a multiple of 16, so the top is too). }
  { NOTE: this parent-side store of h.Tid races the child's startup — the child
    can run before it lands. See the RACE CONTRACT on TThreadHandle. }
  h.Tid := __pxxclone(PXX_CLONE_THREAD, h.StackBase + h.StackSize,
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
{$ifdef CPUX86_64}
  { pthread route: glibc owns the thread and its stack, and the futex handshake
    below cannot work here -- the kernel clears TidWord because of
    CLONE_CHILD_CLEARTID, a flag glibc's thread never had, so a wait on it would
    block forever. pthread_join is the whole of Join here; there is no stack of
    ours to release. Idempotent the same way: PthreadId is zeroed after. }
  if h.PthreadId <> 0 then
  begin
    ignore := c_pthread_join(h.PthreadId, nil);
    h.PthreadId := 0;
    h.TidWord := 0;
    Exit;
  end;
{$endif}
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
