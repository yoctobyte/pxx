{ SPDX-License-Identifier: Zlib }
unit scheduler;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Cooperative single-thread coroutine scheduler (PXX-only; never used in
  compiler.pas, per the FPC/PXX boundary).

  Built on two pieces: the low-level __pxxcoswitch context-switch intrinsic and
  procedural types. Each coroutine owns a heap stack and a saved stack pointer.
  Spawn plants @CoStart as a fresh stack's first return address; the scheduler
  hands the entry proc + arg off through gEntry/gArg right before the first
  switch-in, and CoStart calls entry(arg) through a proc-typed variable. No
  per-target entry shim is needed — the call goes through the normal procedural
  call path.

  Single OS thread, cooperative: a coroutine runs until it calls CoYield (back to
  the scheduler) or its entry returns (marked done, stack freed). RunUntilDone
  round-robins the runnable set until all finish.

  Works on x86-64, i386, aarch64 and arm32 — the only per-target piece is the
  initial-frame layout below (CoSwitch itself lives in the compiler). }

interface

type
  TCoroEntry = procedure(arg: Pointer);

procedure Spawn(entry: TCoroEntry; arg: Pointer);
{ Like Spawn but with an explicit per-coroutine heap-stack size in bytes — the
  RAM-cheap path for constrained devices (e.g. 4-8 KB stacks fit many coroutines
  in little RAM). A canary word at the low end of every stack is checked when the
  coroutine finishes; an overflow that reaches the base aborts with a message. }
procedure SpawnSized(entry: TCoroEntry; arg: Pointer; stackBytes: Int64);
procedure CoYield;
procedure RunUntilDone;

{ Async-I/O reactor (x86-64 only for now). The fd must be non-blocking; on an
  EAGAIN, the coroutine calls WaitReadable/WaitWritable, which parks it on the
  scheduler's epoll instance and yields. RunUntilDone's idle path epoll_waits
  and wakes the coroutines whose fds became ready. On other targets these
  degrade to a plain CoYield (busy-poll). }
procedure WaitReadable(fd: Integer);
procedure WaitWritable(fd: Integer);
procedure SetNonBlocking(fd: Integer);

{ True when the CALLING thread is currently inside a coroutine body, i.e. when
  WaitReadable/WaitWritable will park-and-yield rather than being meaningless.

  This exists so a library that does its own socket I/O can be correct under
  BOTH transports without being handed a flag through every layer: on EAGAIN it
  asks here, and either parks on the reactor (thread stays free) or blocks in
  poll (no reactor to stall). tls13_native's handshake and record layer are the
  first callers -- see feature-tls-provider-abstraction.

  DELIBERATELY NON-ATTACHING, and that is the whole subtlety: CurR attaches a
  fresh reactor slot to the calling thread on first use, so a predicate built on
  it would CONSUME one of the 64 slots merely by asking a question, from any
  thread that never runs a coroutine at all. This walks the table read-only and
  answers False for an unattached thread. }
function InCoroutine: Boolean;

{ Suspend the current coroutine for ms milliseconds without blocking the thread
  (a timerfd parked on the same reactor). On non-reactor targets it degrades to
  a plain CoYield (no real delay). }
procedure CoSleep(ms: Integer);

{ Like WaitReadable but bounded: parks until fd is readable OR ms milliseconds
  elapse (a one-shot timerfd registered alongside fd on the same reactor).
  Returns False when the timer fired. A both-ready race can report False with
  data pending — attempt one nonblocking read before treating False as a hard
  timeout. ms < 0 waits unbounded (plain WaitReadable, always True). }
function WaitReadableTimeout(fd, ms: Integer): Boolean;

{ Writable sibling: parks until fd is writable OR ms milliseconds elapse.
  Same both-ready caveat (attempt the operation once on False); ms < 0 =
  plain WaitWritable, always True. Used for bounded nonblocking connect
  (EINPROGRESS -> wait -> SO_ERROR check). }
function WaitWritableTimeout(fd, ms: Integer): Boolean;

implementation

const
  MAX_CO = 64;
  { Default per-coroutine heap stack. RAISED 64 KB -> 192 KB on 2026-09-01,
    from a measurement rather than a feeling: an https request over the reactor
    (TLS 1.3 handshake -> X.509 parse -> RSA-PSS/ECDSA verify -> trust-store
    walk) CRASHES at 64 KB and at 96 KB, and passes from 128 KB up. A default
    that cannot run this library's own first-class async feature is the wrong
    default. 192 KB is the measured floor plus 50%.

    This is charged PER LIVE COROUTINE (allocated in SpawnSized, freed when the
    body returns), not per MAX_CO slot, so an idle program pays nothing. The
    constrained-device case the header describes is unaffected: it already has
    to call SpawnSized with an explicit size, and 4-8 KB stacks there never went
    through this constant. feature-tls-provider-abstraction }
  CO_STK = 196608;  { 192 KB }
  { Must round-trip through ONE SIGNED machine word: the guard is written and read
    through PW = ^NativeInt, which is 32-bit and signed on i386/arm32/riscv32. A
    value with the high bit set ($C0DECAFE) sign-extends to a negative on load and
    can never compare equal to the constant, which is positive and — since named
    constants above MaxInt are typed Int64 (89366847) — widened to 64 bits for the
    comparison. So keep it below $80000000. }
  CO_CANARY = $4C0DECAF;

{ gettid — per-thread reactor keying. Inlined (not via palthread) so single-
  threaded scheduler users aren't forced onto the --threadsafe runtime by a
  thread-creation dependency. }
{$ifdef CPUX86_64} const SYS_gettid = 186; {$endif}
{$ifdef CPU_I386}  const SYS_gettid = 224; {$endif}
{$ifdef CPU_AARCH64} const SYS_gettid = 178; {$endif}
{$ifdef CPU_ARM32} const SYS_gettid = 224; {$endif}
{$ifdef CPU_RISCV32} const SYS_gettid = 178; {$endif}

{ exit_group — the reactor-exhaustion fatal below terminates the PROCESS itself
  rather than going through Halt. Same inline-rather-than-uses reason as gettid.
  Numbers per target, copied from pxxcio.pas's SysExitGroupNr and per-target for
  the reason recorded there: 231 is x86-64's, and hardcoding it made i386 call
  fgetxattr and exit 0 instead of failing. }
{$ifdef CPUX86_64} const SYS_exit_group = 231; {$endif}
{$ifdef CPU_I386}  const SYS_exit_group = 252; {$endif}
{$ifdef CPU_AARCH64} const SYS_exit_group = 94; {$endif}
{$ifdef CPU_ARM32} const SYS_exit_group = 248; {$endif}
{$ifdef CPU_RISCV32} const SYS_exit_group = 94; {$endif}

{ Reactor flags are identical across all Linux targets; only the syscall
  numbers and the epoll_event layout vary per arch. }
const
  O_NONBLOCK    = $800;
  F_SETFL       = 4;
  EPOLL_CTL_ADD = 1;
  EPOLL_CTL_DEL = 2;
  EPOLLIN       = $001;
  EPOLLOUT      = $004;
  CLOCK_MONOTONIC = 1;
  TFD_NONBLOCK    = $800;

  { --- the guard region below every coroutine stack ---------------------
    PROT_NONE, so it costs ADDRESS SPACE and zero physical memory: the pages
    are never touched, so nothing is ever committed for them.

    WHY A REGION AND NOT A PAGE. The canary at the low end is ONE WORD, so it
    only catches a write that lands ON it -- a single frame larger than the
    remaining stack moves sp straight PAST it and corrupts whatever sits
    below, leaving the canary intact and the yield-time check silent.
    Measured 2026-09-06 on this file, three coroutines with 8 KB stacks and one
    12 KB frame touching its lowest slot: rc 0, every line of expected output,
    and a write ~4 KB below the stack base. A 4 KB guard is leapt by exactly
    that frame; 64 KB is not, and costs the same one mprotect.
    It is a WIDER NET, NOT A PROOF: a frame that clears 64 KB in one step still
    escapes, and only stack probing closes that. feature-tls-provider-abstraction }
  CO_GUARD      = 65536;
  { WRITABLE SLACK BETWEEN THE CANARY AND THE GUARD, and it exists because the
    guard REGRESSED the canary without it. The canary sits at the low end of
    the usable stack, so a coroutine that recurses gently clobbers it and the
    VERY NEXT frame lands in PROT_NONE -- it dies on the spot and never reaches
    the yield where the scheduler would have read the canary and said
    `fatal: coroutine stack overflow (canary clobbered)`. Measured on this file
    before the slack existed: three 8 KB stacks at recursion depth 7/9/12 went
    from rc 217 WITH that message to a bare rc 139 with none.
    So the two mechanisms cover different overflows and must not be stacked
    directly: gradual growth trips the canary and keeps CO_RED bytes of real
    memory to run on until its next yield; a single frame that leaps the canary
    hits the guard. Past CO_RED of gradual growth the guard takes it too, with
    no message -- honest limit, and still better than corrupting a neighbour. }
  CO_RED        = 8192;
  PAGE_SIZE     = 4096;
  PROT_NONE     = 0;
  PROT_RW       = 3;        { PROT_READ or PROT_WRITE }
  MAP_ANON_PRIV = $22;      { MAP_PRIVATE or MAP_ANONYMOUS }

{ Per-arch Linux syscall numbers (verified against the FPC RTL sysnr tables).
  aarch64 / arm32 have no epoll_wait — they use epoll_pwait (two extra args:
  sigmask, sigsetsize, both 0 here). }
{$ifdef CPUX86_64}
const
  SYS_fcntl           = 72;
  SYS_epoll_create1   = 291;
  SYS_epoll_ctl       = 233;
  SYS_epoll_wait      = 232;
  SYS_read            = 0;
  SYS_close           = 3;
  SYS_timerfd_create  = 283;
  SYS_timerfd_settime = 286;
  SYS_mmap            = 9;
  SYS_mprotect        = 10;
  SYS_munmap          = 11;
{$endif}
{$ifdef CPU_I386}
const
  SYS_fcntl           = 55;
  SYS_epoll_create1   = 329;
  SYS_epoll_ctl       = 255;
  SYS_epoll_wait      = 256;
  SYS_read            = 3;
  SYS_close           = 6;
  SYS_timerfd_create  = 322;
  SYS_timerfd_settime = 325;
  { mmap2 (192): its last arg is a PAGE offset, not bytes -- we pass 0, so
    the call is identical to x86-64's mmap. }
  SYS_mmap            = 192;
  SYS_mprotect        = 125;
  SYS_munmap          = 91;
{$endif}
{$ifdef CPU_AARCH64}
const
  SYS_fcntl           = 25;
  SYS_epoll_create1   = 20;
  SYS_epoll_ctl       = 21;
  SYS_epoll_pwait     = 22;
  SYS_read            = 63;
  SYS_close           = 57;
  SYS_timerfd_create  = 85;
  SYS_timerfd_settime = 86;
  SYS_mmap            = 222;
  SYS_mprotect        = 226;
  SYS_munmap          = 215;
{$endif}
{$ifdef CPU_ARM32}
const
  SYS_fcntl           = 55;
  SYS_epoll_create1   = 357;
  SYS_epoll_ctl       = 251;
  SYS_epoll_pwait     = 346;
  SYS_read            = 3;
  SYS_close           = 6;
  SYS_timerfd_create  = 350;
  SYS_timerfd_settime = 353;
  { mmap2, page offset, 0 here -- see the i386 note. }
  SYS_mmap            = 192;
  SYS_mprotect        = 125;
  SYS_munmap          = 91;
{$endif}
{ riscv32 is an ASM-GENERIC port, so its numbers are aarch64's and NOT arm32's,
  which is the mistake the shape of this file invites -- the two are both 32-bit
  and adjacent in every table here, and a number from the wrong table is not a
  compile error, it is a different syscall at runtime. Like aarch64 it has
  epoll_pwait and no epoll_wait. }
{$ifdef CPU_RISCV32}
const
  SYS_fcntl           = 25;
  SYS_epoll_create1   = 20;
  SYS_epoll_ctl       = 21;
  SYS_epoll_pwait     = 22;
  SYS_read            = 63;
  SYS_close           = 57;
  SYS_timerfd_create  = 85;
  { timerfd_settime64. rv32 is time64-only and has NO timerfd_settime(86):
    measured -38 ENOSYS, while 411 answers 0 on the same fd. The itimerspec
    it wants is four 64-bit fields, which is why ArmOneShotTimer branches on
    SCHED_TIME64 and not on CPU64. timerfd_create(85) is unaffected -- it
    takes no timespec and works here. }
  SYS_timerfd_settime = 411;
  SYS_mmap            = 222;
  SYS_mprotect        = 226;
  SYS_munmap          = 215;
{$endif}

type
  { Linux epoll_event: u32 events then u64 data. Only x86 packs it (data at
    offset 4, size 12); on aarch64/arm32 the u64 is naturally 8-aligned, so an
    explicit pad word puts data at offset 8 (size 16). The data word carries the
    waiting coroutine's id straight back from epoll_wait/epoll_pwait. }
{$ifdef CPUX86_64}
  TEpollEvent = packed record events: LongWord; data: Int64; end;
{$endif}
{$ifdef CPU_I386}
  TEpollEvent = packed record events: LongWord; data: Int64; end;
{$endif}
{$ifdef CPU_AARCH64}
  TEpollEvent = record events: LongWord; _pad: LongWord; data: Int64; end;
{$endif}
{$ifdef CPU_ARM32}
  TEpollEvent = record events: LongWord; _pad: LongWord; data: Int64; end;
{$endif}
{ riscv32 aligns a u64 to 8 like aarch64/arm32 do, so it takes the PADDED shape
  (data at offset 8, size 16), not i386's packed one. }
{$ifdef CPU_RISCV32}
  TEpollEvent = record events: LongWord; _pad: LongWord; data: Int64; end;
{$endif}

type
  PW = ^NativeInt;  { pointer-sized machine-word access at an address }
  PQ = ^Int64;      { an explicitly 64-BIT field, whatever the machine word is }

{ The kernel's timespec is 64-bit on riscv32 EVEN THOUGH the machine word is 32
  -- rv32 is time64-only. So the itimerspec layout cannot be selected by CPU64,
  which is what ArmOneShotTimer used to do and what put it on the 8/12 offsets.
  Same rule, same target, as PAL_TIME64 in platform_backend.pas. }
{$ifdef CPU_RISCV32}{$define SCHED_TIME64}{$endif}

const
{ Independent reactors, one per OS thread that ever calls into the scheduler.
  Sized to PAR_MAX_WORKERS (palparallel), the hard ceiling on workers a single
  parallel-for can fan to — so a `parallel for` containing async work can never
  exhaust the table however wide it runs or however large the host. Not `uses`d
  from here: scheduler must not depend on palparallel, so the number is repeated
  and this comment is the link. Both other tables in this file (MAX_CO, and
  sockets.pas's ErrnoSlot) are 64 for the same reason.

  This was 16, with the comment "one per OS thread / core" — a statement about
  the host that nothing enforced. Threads above the ceiling then took the
  fallthrough in CurR and silently adopted a LIVE thread's reactor.
  Note the dial is the WORKER count, not the core count: PXXSetParForWorkers
  makes it reachable on any host, so 12-core hardware reproduces it fine and
  the "needs a 24-core box" reading was a property of the DEFAULT worker count.
  bug-a-the-17th-thread-silently-aliases-reactor-slot-0 }
{$ifdef PXX_SCHED_TINY_REACTORS}
  MAX_REACTORS = 2;    { test-only: makes the exhaustion arm reachable with 3 threads }
{$else}
  MAX_REACTORS = 64;
{$endif}

const
  { Upper bound on the loser-side wait in the exhaustion fatal below. Sized to
    be unreachable in practice (the winner needs one write syscall) while still
    being a bound: ~1e7 lock-prefixed compare-exchanges is a fraction of a
    second, so a wedged winner costs a late fatal, never a hung process. }
  FATAL_SPIN_MAX = 10000000;

type
  TReactor = record
    coSp    : array[0..MAX_CO-1] of Int64;       { saved stack pointer }
    coStk   : array[0..MAX_CO-1] of Int64;       { usable stack base -- the canary lives here }
    coStkMap: array[0..MAX_CO-1] of Int64;       { full mmap length, 0 = GetMem'd (no guard) }
    coState : array[0..MAX_CO-1] of Integer;     { 0=free 1=runnable 2=done 3=io-blocked }
    coEntry : array[0..MAX_CO-1] of TCoroEntry;  { body to run on first switch-in }
    coArg   : array[0..MAX_CO-1] of Pointer;
    coCount : Integer;
    curCo   : Integer;                           { running coroutine, -1 = scheduler }
    schedSp : Int64;                             { scheduler's own saved sp }
    gEntry  : TCoroEntry;                        { handoff to CoStart }
    gArg    : Pointer;
    epfd    : Integer;                           { epoll instance, 0 = not created }
    tid     : Int64;                             { owning thread id, 0 = free slot }
    used    : Integer;                           { 1 = attached to a thread }
  end;
  PReactor = ^TReactor;

var
  reactors : array[0..MAX_REACTORS-1] of TReactor;
  regLock  : Integer;   { atomic spinlock guarding slot attachment (0=free 1=held) }
  fatalOnce: Integer;   { 0 until a thread claims the reactor-exhaustion fatal }
  fatalDone: Integer;   { 0 until that thread has finished WRITING it }

function SelfTid: Int64;
begin
  SelfTid := __pxxrawsyscall(SYS_gettid, 0, 0, 0, 0, 0, 0);
end;

{ Resolve the calling thread's reactor, attaching a fresh slot on first use.
  Per-thread state without threadvar, keyed on the kernel tid. The fast path
  (already attached) is lock-free; attachment is guarded by a tiny atomic
  spinlock (contended only briefly at worker-thread startup). }
function InCoroutine: Boolean;
var me: Int64; i: Integer;
begin
  { read-only twin of CurR's fast path -- never attaches, never locks }
  InCoroutine := False;
  me := SelfTid;
  for i := 0 to MAX_REACTORS - 1 do
    if (reactors[i].used = 1) and (reactors[i].tid = me) then
    begin
      InCoroutine := reactors[i].curCo >= 0;   { -1 = the scheduler itself }
      Exit;
    end;
end;

function CurR: PReactor;
var me, ignore: Int64; i, slot, spins: Integer;
begin
  me := SelfTid;
  for i := 0 to MAX_REACTORS - 1 do
    if (reactors[i].used = 1) and (reactors[i].tid = me) then
    begin CurR := @reactors[i]; Exit; end;
  while __pxxatomic_cas(@regLock, 0, 1) <> 0 do ;   { acquire }
  { -1 is the sentinel, NOT a valid slot: exhaustion has to be a decision here.
    This read `slot := 0`, so when every reactor was already `used` the loop
    matched nothing, the initializer survived, and the caller took over slot 0
    from the thread that owned it -- two OS threads driving one coroutine table,
    surfacing later as a clobbered stack canary that points at the coroutine
    rather than at the aliasing. Refuse loudly instead, mirroring the MAX_CO arm
    in SpawnSized below; a shared reactor is not survivable the way sockets.pas's
    deliberately-shared errno slot is.
    bug-a-the-17th-thread-silently-aliases-reactor-slot-0 }
  slot := -1;
  spins := 0;
  for i := 0 to MAX_REACTORS - 1 do
    if reactors[i].used = 0 then begin slot := i; Break; end;
  if slot < 0 then
  begin
    { EXACTLY ONE thread may report, and it must not hold regLock while it does.
      That half is still measured, not defensive: Halt cannot be serialised into
      safety here, because its exit path joins the worker threads. Keeping
      regLock hung the process (exit 124 by `timeout` at 4, 8 and 20 workers);
      releasing it and parking the losers hung it too, for the real reason -- a
      parked thread is one the join waits on forever. A hang is not an
      improvement on a lie. So: release the lock, let exactly one thread report,
      and let every refused thread call Halt.

      This arm called exit_group through __pxxrawsyscall from 2026-08-28 to
      2026-08-29, because Halt's exit status was UNRELIABLE: same binary, same
      width, repeated, 4 workers gave 0, 216, 0 and 8 workers gave 0, 0, 0 -- a
      fatal reporting SUCCESS to any harness reading the status.

      That was a COMPILER bug, now fixed: Halt(n) on x86-64 and arm32 emitted
      the `exit` syscall instead of `exit_group`, so it ended only the calling
      thread and the process status fell to whichever thread exited last.
      bug-b-concurrent-halt-from-several-threads-exits-0.

      The workaround is reverted deliberately and not merely tidied away.
      Leaving it would have left test_sched_reactor_exhaustion passing whether
      or not the compiler was fixed -- a green test guarding nothing, which is
      what a workaround becomes the moment the bug behind it closes. }
    ignore := __pxxatomic_xchg(@regLock, 0);
    if __pxxatomic_cas(@fatalOnce, 0, 1) = 0 then
    begin
      writeln('fatal: scheduler out of reactor slots (MAX_REACTORS)');
      ignore := __pxxatomic_xchg(@fatalDone, 1);
    end
    else
      { A LOSER MUST NOT TAKE THE PROCESS DOWN WHILE THE WINNER IS WRITING.
        Halt is exit_group now, so the first refused thread to reach it ends
        every thread -- including the one mid-writeln. That lost the message
        outright: status 216 with an empty log, i.e. a fatal that reports its
        number and not its reason. Measured here at 24 workers, 1 run in 15 with
        the output on a FILE (0 in 15 at 4 workers, and 0 in 12 on a pipe --
        which is why the harness saw it on `seven` and the pipe-shaped local
        check did not). regression-test-threads-test-sched-reactor-exhaustion-5.
        Bounded, so a winner that never arrives degrades to a slightly-late
        fatal rather than to a hang -- exhaustion must stay loud, and a hang is
        the one outcome worse than a quiet exit. }
      while (__pxxatomic_cas(@fatalDone, 0, 0) = 0) and (spins < FATAL_SPIN_MAX) do
        Inc(spins);
    Halt(216);
  end;
  reactors[slot].coCount := 0;
  reactors[slot].curCo   := -1;
  reactors[slot].epfd    := 0;
  reactors[slot].tid     := me;
  reactors[slot].used    := 1;
  ignore := __pxxatomic_xchg(@regLock, 0);          { release }
  CurR := @reactors[slot];
end;

{ First-entry trampoline. Runs on the coroutine's own stack the first time the
  scheduler switches into it; the scheduler set gEntry/gArg just before. After
  the body returns, mark done and switch back — this never returns. }
procedure CoStart;
var e: TCoroEntry; a: Pointer; r: PReactor;
begin
  r := CurR;
  e := r^.gEntry;
  a := r^.gArg;
  e(a);
  r := CurR;                 { same thread; re-resolve after the body ran }
  r^.coState[r^.curCo] := 2;
  __pxxcoswitch(@r^.coSp[r^.curCo], @r^.schedSp);
end;

{ Build the initial saved-state frame the first CoSwitch-in pops. The slot order
  must mirror the per-target CoSwitch's pop sequence (see coroutine_emit.inc):
  exc_top first (lowest address, popped first), then the callee-saved registers,
  then the return address (= CoStart). PW = ^NativeInt writes one machine word,
  so the slot stride is the target pointer size automatically. }
procedure Spawn(entry: TCoroEntry; arg: Pointer);
begin
  SpawnSized(entry, arg, CO_STK);
end;

procedure SpawnSized(entry: TCoroEntry; arg: Pointer; stackBytes: Int64);
var id, i2: Integer; stk, top, mapLen, mapBase, usable, ignoreRc: Int64; r: PReactor;
begin
  r := CurR;
  { reuse a freed slot (state 0) before growing — bounds coCount so a program
    that spawns per-connection over its lifetime does not exceed MAX_CO. }
  id := -1;
  for i2 := 0 to r^.coCount - 1 do
    if r^.coState[i2] = 0 then begin id := i2; Break; end;
  if id < 0 then begin id := r^.coCount; Inc(r^.coCount); end;
  if id >= MAX_CO then
  begin writeln('fatal: scheduler out of coroutine slots (MAX_CO)'); Halt(216); end;
  { A GUARDED MAPPING WHERE THE KERNEL OFFERS ONE, GetMem WHERE IT DOES NOT.
    The fallback is not a degraded mode to be ashamed of -- it is what every
    target without these five syscall numbers gets, and the canary below still
    runs there. mmap failing is handled the same way, because a coroutine that
    runs is what the caller asked for and there is no channel to report
    "your stack is unguarded". }
  stk := 0;
  mapLen := 0;
  { [ CO_GUARD PROT_NONE ][ CO_RED slack ][ canary ][ ...usable stack... ] top }
  usable := ((stackBytes + PAGE_SIZE - 1) div PAGE_SIZE) * PAGE_SIZE;
  mapBase := __pxxrawsyscall(SYS_mmap, 0, usable + CO_GUARD + CO_RED, PROT_RW,
                             MAP_ANON_PRIV, -1, 0);
  if mapBase > 0 then
  begin
    { Fail CLOSED, not open: if the region cannot be made PROT_NONE then this
      mapping has no guard and is worth nothing over the heap, so give it back
      rather than keep a stack that merely LOOKS protected. }
    if __pxxrawsyscall(SYS_mprotect, mapBase, CO_GUARD, PROT_NONE, 0, 0, 0) = 0 then
    begin
      mapLen := usable + CO_GUARD + CO_RED;
      stk := mapBase + CO_GUARD + CO_RED;
      stackBytes := usable;
    end
    else
      ignoreRc := __pxxrawsyscall(SYS_munmap, mapBase, usable + CO_GUARD + CO_RED,
                                  0, 0, 0, 0);
  end;
  if stk = 0 then stk := Int64(GetMem(stackBytes));
  PW(stk)^ := CO_CANARY;          { overflow guard at the low end of the stack }
  top := stk + stackBytes;
  top := top - (top mod 16);   { 16-align down }
{$ifdef CPU_I386}
  { i386 pops: exc, edi, esi, ebx, ebp, ret — 6 dwords. }
  top := top - 24;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 4)^  := 0;                { edi }
  PW(top + 8)^  := 0;                { esi }
  PW(top + 12)^ := 0;                { ebx }
  PW(top + 16)^ := 0;                { ebp }
  PW(top + 20)^ := Int64(@CoStart);  { return address -> CoStart }
{$else}
{$ifdef CPU_AARCH64}
  { aarch64 restores: exc(16B slot), then x29/x30, x27/x28 ... x19/x20 — 112
    bytes. Only exc_top (0) and the x30 slot (= CoStart) must be set; the other
    callee-saved slots are dead on first entry. CoSwitch ret jumps to x30. }
  top := top - 112;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 24)^ := Int64(@CoStart);  { x30 -> CoStart }
{$else}
{$ifdef CPU_ARM32}
  { arm32 restores: exc, then r4..r11, lr — 40 bytes. Only exc_top (0) and the
    lr slot (= CoStart) matter; the rest are dead on first entry. CoSwitch
    bx lr jumps to lr. }
  top := top - 40;
  PW(top + 0)^  := 0;                { exc_top }
  PW(top + 36)^ := Int64(@CoStart);  { lr -> CoStart }
{$else}
{$ifdef CPU_RISCV32}
  { riscv32 restores: exc, s0, ra, pad — SIXTEEN bytes, and the pad is what
    keeps sp 16-byte aligned as the psABI requires. Three slots rather than
    thirteen because this backend's codegen never touches s1-s11; the same fact
    the exception jmpbuf relies on. This layout and the CoSwitch stub in
    compiler/coroutine_emit.inc are ONE contract -- change either and change
    both, which is why each says so. }
  top := top - 16;
  PW(top + 0)^ := 0;                 { exc_top }
  PW(top + 8)^ := Int64(@CoStart);   { ra -> CoStart }
{$else}
  { x86-64 pops: exc, r15, r14, r13, r12, rbx, rbp, ret — 8 qwords; rsp at
    CoStart entry must be == 8 (mod 16). }
  top := top - 8;
  top := top - 64;
  PW(top + 0)^  := 0;                { exc_top -> fresh chain on this stack }
  PW(top + 8)^  := 0;                { r15 }
  PW(top + 16)^ := 0;                { r14 }
  PW(top + 24)^ := 0;                { r13 }
  PW(top + 32)^ := 0;                { r12 }
  PW(top + 40)^ := 0;                { rbx }
  PW(top + 48)^ := 0;                { rbp }
  PW(top + 56)^ := Int64(@CoStart);  { return address -> CoStart }
{$endif}
{$endif}
{$endif}
{$endif}
  r^.coSp[id]    := top;
  r^.coStk[id]   := stk;
  r^.coStkMap[id]:= mapLen;
  r^.coState[id] := 1;
  r^.coEntry[id] := entry;
  r^.coArg[id]   := arg;
end;

{ Suspend the current coroutine, returning control to the scheduler. }
procedure CoYield;
var r: PReactor;
begin
  r := CurR;
  __pxxcoswitch(@r^.coSp[r^.curCo], @r^.schedSp);
end;

{ Mark fd non-blocking so read/write return EAGAIN instead of blocking the whole
  scheduler thread. (v1 sets only O_NONBLOCK; it does not preserve other flags.) }
procedure SetNonBlocking(fd: Integer);
var rc: Int64;
begin
  rc := __pxxrawsyscall(SYS_fcntl, fd, F_SETFL, O_NONBLOCK, 0, 0, 0);
end;

{ Park the current coroutine on epoll until fd is ready for the given event,
  then yield. On resume the fd is removed from the set (one-shot add/del).
  Portable across all four targets via the per-arch SYS_* numbers. }
procedure WaitIO(fd, events: Integer);
var ev: TEpollEvent; rc: Int64; r: PReactor;
begin
  r := CurR;
  if r^.epfd = 0 then
    r^.epfd := Integer(__pxxrawsyscall(SYS_epoll_create1, 0, 0, 0, 0, 0, 0));
  ev.events := events;
  ev.data := r^.curCo;
  rc := __pxxrawsyscall(SYS_epoll_ctl, r^.epfd, EPOLL_CTL_ADD, fd, Int64(@ev), 0, 0);
  r^.coState[r^.curCo] := 3;                   { io-blocked }
  __pxxcoswitch(@r^.coSp[r^.curCo], @r^.schedSp);   { -> scheduler }
  rc := __pxxrawsyscall(SYS_epoll_ctl, r^.epfd, EPOLL_CTL_DEL, fd, 0, 0, 0);
end;

procedure WaitReadable(fd: Integer); begin WaitIO(fd, EPOLLIN);  end;
procedure WaitWritable(fd: Integer); begin WaitIO(fd, EPOLLOUT); end;

{ One-shot relative timer as a readable fd: arm a timerfd, park on the reactor
  until it fires, drain the expiration count, close. itimerspec is two timespecs
  (it_interval, it_value); timespec is tv_sec then tv_nsec with the machine word
  width, so it_value starts at one timespec (16 bytes on 64-bit, 8 on 32-bit).
  PW = ^NativeInt writes the matching word width. }
{ Arm a fresh one-shot non-blocking timerfd for ms milliseconds and return it.
  itimerspec is two timespecs (it_interval, it_value); timespec is tv_sec then
  tv_nsec, so it_value starts at one timespec -- 16 bytes where the timespec is
  64-bit (every 64-bit target AND riscv32, which is time64-only), 8 bytes on the
  legacy-time32 32-bit targets. The selector is SCHED_TIME64, NOT CPU64. }
function ArmOneShotTimer(ms: Integer): Integer;
var tfd, i: Integer; spec: array[0..31] of Byte; base, rc: Int64;
begin
  tfd := Integer(__pxxrawsyscall(SYS_timerfd_create, CLOCK_MONOTONIC, TFD_NONBLOCK, 0, 0, 0, 0));
  for i := 0 to 31 do spec[i] := 0;        { it_interval = 0 (one-shot) }
  base := Int64(@spec[0]);
{$ifdef CPU64}
  PW(base + 16)^ := ms div 1000;             { it_value.tv_sec }
  PW(base + 24)^ := (ms mod 1000) * 1000000; { it_value.tv_nsec }
{$else}
{$ifdef SCHED_TIME64}
  { 32-bit machine, 64-bit timespec: the 64-bit OFFSETS with explicitly 64-bit
    writes. Not PW at 16/24 -- that would be a 4-byte store whose high half
    happens to be zero only because `spec' was cleared above, which is a fact
    about this function rather than about the struct. }
  PQ(base + 16)^ := ms div 1000;             { it_value.tv_sec }
  PQ(base + 24)^ := (ms mod 1000) * 1000000; { it_value.tv_nsec }
{$else}
  PW(base + 8)^  := ms div 1000;             { it_value.tv_sec  (8-byte timespec) }
  PW(base + 12)^ := (ms mod 1000) * 1000000; { it_value.tv_nsec }
{$endif}
{$endif}
  rc := __pxxrawsyscall(SYS_timerfd_settime, tfd, 0, base, 0, 0, 0);
  ArmOneShotTimer := tfd;
end;

procedure CoSleep(ms: Integer);
var tfd: Integer; buf, rc: Int64;
begin
  tfd := ArmOneShotTimer(ms);
  WaitReadable(tfd);
  rc := __pxxrawsyscall(SYS_read, tfd, Int64(@buf), 8, 0, 0, 0);  { drain expirations }
  rc := __pxxrawsyscall(SYS_close, tfd, 0, 0, 0, 0, 0);
end;

{ Shared body of WaitReadableTimeout / WaitWritableTimeout: park on fd (for
  the given epoll events) and a one-shot timerfd; True = fd readied first. }
function WaitIOTimeout(fd, events, ms: Integer): Boolean;
var
  tfd: Integer;
  ev, tev: TEpollEvent;
  rc, got, buf: Int64;
  r: PReactor;
begin
  r := CurR;
  if r^.epfd = 0 then
    r^.epfd := Integer(__pxxrawsyscall(SYS_epoll_create1, 0, 0, 0, 0, 0, 0));
  tfd := ArmOneShotTimer(ms);
  { park on BOTH fds; whichever readies first wakes this coroutine }
  ev.events := events;
  ev.data := r^.curCo;
  tev.events := EPOLLIN;   { the timerfd is always a read wait }
  tev.data := r^.curCo;
  rc := __pxxrawsyscall(SYS_epoll_ctl, r^.epfd, EPOLL_CTL_ADD, fd, Int64(@ev), 0, 0);
  rc := __pxxrawsyscall(SYS_epoll_ctl, r^.epfd, EPOLL_CTL_ADD, tfd, Int64(@tev), 0, 0);
  r^.coState[r^.curCo] := 3;                   { io-blocked }
  __pxxcoswitch(@r^.coSp[r^.curCo], @r^.schedSp);   { -> scheduler }
  rc := __pxxrawsyscall(SYS_epoll_ctl, r^.epfd, EPOLL_CTL_DEL, fd, 0, 0, 0);
  rc := __pxxrawsyscall(SYS_epoll_ctl, r^.epfd, EPOLL_CTL_DEL, tfd, 0, 0, 0);
  { non-blocking read: 8 bytes = the timer fired first (or simultaneously) }
  got := __pxxrawsyscall(SYS_read, tfd, Int64(@buf), 8, 0, 0, 0);
  rc := __pxxrawsyscall(SYS_close, tfd, 0, 0, 0, 0, 0);
  WaitIOTimeout := got <> 8;
end;

function WaitReadableTimeout(fd, ms: Integer): Boolean;
begin
  if ms < 0 then
  begin
    WaitReadable(fd);
    WaitReadableTimeout := True;
    Exit;
  end;
  WaitReadableTimeout := WaitIOTimeout(fd, EPOLLIN, ms);
end;

function WaitWritableTimeout(fd, ms: Integer): Boolean;
begin
  if ms < 0 then
  begin
    WaitWritable(fd);
    WaitWritableTimeout := True;
    Exit;
  end;
  WaitWritableTimeout := WaitIOTimeout(fd, EPOLLOUT, ms);
end;

{ Round-robin every runnable coroutine; when none are runnable but some are
  blocked on I/O, epoll_wait for readiness and wake them. Ends when nothing is
  runnable and nothing is blocked. }
procedure RunUntilDone;
var i, anyRunnable, anyBlocked: Integer;
    n, k, cid: Integer;
    freeRc: Int64;
    evs: array[0..MAX_CO-1] of TEpollEvent;
    r: PReactor;
begin
  r := CurR;
  repeat
    anyRunnable := 0;
    for i := 0 to r^.coCount - 1 do
      if r^.coState[i] = 1 then
      begin
        anyRunnable := 1;
        r^.curCo := i;
        r^.gEntry := r^.coEntry[i];
        r^.gArg := r^.coArg[i];
        __pxxcoswitch(@r^.schedSp, @r^.coSp[i]);   { run i until it yields/finishes }
        { CHECK THE CANARY ON EVERY RETURN TO THE SCHEDULER, not only on
          completion. It used to sit inside the `coState = 2` arm below, so a
          coroutine that overflowed and then died before finishing was never
          checked at all -- it never reached `done`. Every yield is a free
          checkpoint; this is one load and one compare.

          WHAT IT CATCHES, measured with a control in both directions rather
          than claimed: a coroutine that clobbers the canary, yields, and then
          dies. Old site -> silent SIGSEGV, no output, rc 139. New site ->
          `fatal: coroutine stack overflow (canary clobbered)`, rc 217. That is
          the shape of the real TLS failure.

          WHAT IT STILL DOES NOT CATCH, stated because the honest limit matters
          more than the win: an overflow that runs off the end and faults
          IMMEDIATELY, before it can yield. A TLS handshake on a 64 KB stack is
          exactly that -- it segfaults with no output, with this check in place.
          Nothing here rescues it, which is why CO_STK was RAISED as well; this
          check narrows the window, it does not close it. A guard page below
          each stack would, and would cost an mmap per coroutine.
          feature-tls-provider-abstraction }
        if PW(r^.coStk[i])^ <> CO_CANARY then
        begin
          writeln('fatal: coroutine stack overflow (canary clobbered)');
          Halt(217);
        end;
        { AND THE SAME QUESTION ASKED OF THE STACK POINTER, because the canary
          is a WORD and this is a RANGE. A single frame larger than the
          remaining stack steps over the canary without touching it -- the
          canary reads correct and the write went below the base. One compare,
          no memory traffic, and it needs no guard page, so it covers the
          GetMem fallback too.
          It is not a superset of the canary and does not replace it: this sees
          only where sp SITS at the yield, so a deep frame that returns before
          yielding is invisible here and visible there. Two instruments, two
          apertures. Measured 2026-09-06: a 12 KB frame on an 8 KB stack, which
          the canary passes clean. }
        if (r^.coState[i] <> 2) and (r^.coSp[i] <> 0) and
           (r^.coSp[i] < r^.coStk[i]) then
        begin
          writeln('fatal: coroutine stack overflow (sp below its stack base)');
          Halt(217);
        end;
        if r^.coState[i] = 2 then
        begin
          { munmap releases the guard region with the stack; the base is CO_GUARD
            BELOW the usable base recorded in coStk. }
          if r^.coStkMap[i] <> 0 then
            freeRc := __pxxrawsyscall(SYS_munmap, r^.coStk[i] - CO_GUARD - CO_RED,
                                      r^.coStkMap[i], 0, 0, 0, 0)
          else
            FreeMem(Pointer(r^.coStk[i]));
          r^.coStkMap[i] := 0;
          r^.coState[i] := 0;   { free the slot for reuse by a later Spawn }
        end;
      end;
    anyBlocked := 0;
    for i := 0 to r^.coCount - 1 do
      if r^.coState[i] = 3 then anyBlocked := 1;
    if (anyRunnable = 0) and (anyBlocked = 1) then
    begin
      { Nothing to run but coroutines wait on I/O: block here until an fd is
        ready, then mark the parked coroutines runnable (data = their id).
        x86 uses epoll_wait; aarch64/arm32 only have epoll_pwait (sigmask=0,
        sigsetsize=0). }
{$ifdef CPUX86_64}
      n := Integer(__pxxrawsyscall(SYS_epoll_wait, r^.epfd, Int64(@evs[0]), MAX_CO, -1, 0, 0));
{$endif}
{$ifdef CPU_I386}
      n := Integer(__pxxrawsyscall(SYS_epoll_wait, r^.epfd, Int64(@evs[0]), MAX_CO, -1, 0, 0));
{$endif}
{$ifdef CPU_AARCH64}
      n := Integer(__pxxrawsyscall(SYS_epoll_pwait, r^.epfd, Int64(@evs[0]), MAX_CO, -1, 0, 0));
{$endif}
{$ifdef CPU_ARM32}
      n := Integer(__pxxrawsyscall(SYS_epoll_pwait, r^.epfd, Int64(@evs[0]), MAX_CO, -1, 0, 0));
{$endif}
{$ifdef CPU_RISCV32}
      n := Integer(__pxxrawsyscall(SYS_epoll_pwait, r^.epfd, Int64(@evs[0]), MAX_CO, -1, 0, 0));
{$endif}
      for k := 0 to n - 1 do
      begin
        cid := Integer(evs[k].data);
        r^.coState[cid] := 1;
      end;
    end;
  until (anyRunnable = 0) and (anyBlocked = 0);
  r^.curCo := -1;
end;

end.
