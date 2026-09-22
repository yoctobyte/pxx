program test_tls_base;
{ __pxxTlsBase: a per-thread slot that is genuinely distinct per thread, reachable
  without a syscall (feature-a-thread-local-storage-via-clone-settls).

  The ticket's premise was that PXX_CLONE_THREAD omits CLONE_SETTLS, so every
  thread inherits the parent's fs base and an fs:-relative slot silently aliases.
  That observation is true; the prescribed remedy -- pass a tls argument through
  clone -- is not the smallest one. arch_prctl(ARCH_SET_GS) works on the CALLING
  thread, so a thread can install its own block as its first act, and the whole
  fix is one read-side intrinsic instead of a sixth __pxxclone argument plus four
  backend changes.

  Three phases, because there are three ways to get a block:
    0. THE MAIN THREAD -- code at the ELF entry point installs a BSS block before
       any frontend's code runs, so __pxxTlsBase works there with nothing done.
       It passes through no clone stub and a static binary starts with fs base 0,
       so this is the one that used to fault outright.
    A. AUTOMATIC -- the clone stub carves 128 bytes off the top of the child's
       stack and arch_prctl's it before any Pascal runs. Nothing in the RTL or
       the program has to remember, which is the point: the failure mode of
       forgetting is not a null pointer but the parent's block.
    B. MANUAL -- arch_prctl from the thread itself. Nothing in the runtime needs
       this any more, but it is the primitive both of the above are built out of,
       and a program with its own idea of where its block should live uses it.

  What each check catches:
    - blocks distinct   : the aliasing bug itself. If arch_prctl were not
                          per-thread, every child would end up with one base and
                          the tags would collide.
                          THIS IS A STATEMENT ABOUT THREADS THAT ARE ALIVE AT
                          THE SAME TIME, and until 2026-09-22 it was written as
                          if it were a statement about the process. It is not:
                          the stub's block lives at the top of the child's
                          stack, that stack is munmap'd when the thread dies
                          (by Join, or by ReapSweep on the next
                          PalThreadCreate), and Linux hands the same address
                          back to the next thread. So two phase-A children that
                          never coexisted legitimately reported ONE base, the
                          symmetric pair fired twice, and the test printed
                          `errors=2` on 7-11% of runs with nothing wrong.
                          Phase A now holds its four threads open across the
                          comparison; phase A2 exercises the recycled path on
                          purpose. Measured: 10/300 without the barrier,
                          0/600 with it, and the cause confirmed by stubbing
                          ReapSweep (4 identical bases -> 4 distinct ones).
    - main tag intact   : children installing a base must not disturb the parent's.
                          Reads AFTER the joins, so it is the parent's own fs that
                          is under test, not a copy.
    - self-pointer      : __pxxTlsBase must equal the block address the thread
                          installed -- the slot-0 convention the intrinsic relies
                          on. A wrong fs:[0] encoding would still return SOMETHING
                          and only this equality would notice.
    - churn loop        : each thread re-reads its slot 20000 times while the
                          others do the same. A base that is shared rather than
                          per-thread shows up as a torn tag here even when the
                          post-join snapshot happens to look right. }

uses palthread, palfutex;

const
  SYS_arch_prctl = 158;
  ARCH_SET_GS    = $1001;
  NTHREADS       = 4;
  CHURN          = 20000;
  { The phase-A release barrier. 100 * 50 ms = 5 s, against a parent that sets
    the word microseconds after the last PalThreadCreate returns. Bounded on
    purpose: a test that HANGS is worse than one that fails, and a child that
    never sees the word says so instead of parking a tier. }
  BARRIER_TRIES    = 100;
  BARRIER_SLICE_NS = 50 * 1000 * 1000;

type
  PInt64 = ^Int64;
  { 8 slots. Slot 0 is the block's own address (the convention __pxxTlsBase
    reads through); slot 1 is this test's per-thread tag. }
  { Sixteen slots, i.e. the whole TLS_BLOCK_SIZE, not just the part this test
    writes: phase B installs one of these AS the thread's block, so a short one
    would leave the runtime's own slots pointing past its end. }
  TTlsBlock = array[0..15] of Int64;

var
  Blocks: array[0..NTHREADS] of TTlsBlock;   { [NTHREADS] is the main thread's }
  Handles: array[0..NTHREADS - 1] of TThreadHandle;
  AutoBase: array[0..NTHREADS - 1] of Pointer;   { each child's stub-installed block }
  Errs: array[0..NTHREADS - 1] of Integer;
  { The phase-A barrier: the parent sets GoA once every child exists, so no
    phase-A child can exit before the last one has started. BarrierLate[idx]
    records a child that gave up waiting -- see the phase-A comment for why
    that has to be an ERROR and not a silent weakening. }
  GoA: Integer;
  BarrierLate: array[0..NTHREADS - 1] of Integer;
  i, j, errors: Integer;

{ Make block b the calling thread's TLS block. }
procedure InstallTls(b: PInt64);
var r: Int64;
begin
  b^ := Int64(PtrUInt(b));   { slot 0 = self, so fs:[0] yields the base }
  r := __pxxrawsyscall(SYS_arch_prctl, ARCH_SET_GS, Int64(PtrUInt(b)), 0, 0, 0, 0);
  if r <> 0 then
  begin
    Writeln('arch_prctl failed: ', r);
    Halt(1);
  end;
end;

{ SLOT 15, THE LAST ONE, chosen so this test stops moving. The map in defs.inc
  grows from the BOTTOM -- slot 0 self-pointer, 1 the --threadsafe I/O lock's
  cached tid, 2/3 its stack bounds, 4..7 the signal dispatch stub's parked
  fields, 8..11 the exception state -- and this test's tag has been evicted
  FOUR TIMES IN ONE DAY by that growth, each time silently: a tag in slot 1
  makes every Writeln here see a bogus owner id, and one in slot 8 makes the
  unwinder walk a chain head this test invented.
  Taking the top slot instead of TLS_SLOT_FIRST_FREE means the next runtime
  consumer does not move this file; if the map ever reaches 15, TLS_BLOCK_SIZE
  has to grow anyway and that is the moment to look here. The zero-check below
  still reads TLS_SLOT_FIRST_FREE's neighbourhood, which is the assertion that
  caught all four evictions -- it is about slots this test does NOT own. }
function TlsSlot(n: Integer): PInt64;
begin
  TlsSlot := PInt64(PtrUInt(__pxxTlsBase) + PtrUInt(n * 8));
end;

{ Block until the parent has created every phase-A thread.

  Returning early is not an option and neither is spinning forever, so this
  waits on a futex with a bound and REPORTS giving up. A child that times out
  may have outlived nobody, so the distinctness comparison the parent runs
  afterwards is not trustworthy -- and an untrustworthy comparison that prints
  the same `errors=0` as a trustworthy one is the exact shape this whole file
  was failing on. BarrierLate is read back as an error for that reason. }
procedure WaitForGo(idx: Integer);
var spins, r: Integer;
begin
  spins := 0;
  while (GoA = 0) and (spins < BARRIER_TRIES) do
  begin
    { -EAGAIN (the word already moved) and -ETIMEDOUT are both answered by
      re-reading GoA at the top, so the result is deliberately not branched on. }
    r := PalFutexWaitTimeout(@GoA, 0, BARRIER_SLICE_NS);
    if r = 0 then ;
    Inc(spins);
  end;
  if GoA = 0 then BarrierLate[idx] := 1;
end;

{ Phase A: use the block the CLONE STUB installed. No InstallTls here -- that is
  the whole assertion. }
procedure AutoBody(arg: Pointer);
var idx, k: Integer; tag: Int64;
begin
  idx := Integer(PtrUInt(arg));
  { Hold every phase-A thread alive until the last one has started. Phase A2
    below sets GoA once and leaves it set, so this returns immediately there --
    that phase WANTS the threads serialised. }
  WaitForGo(idx);
  AutoBase[idx] := __pxxTlsBase;
  { slot 0 must be the block's own address: the stub wrote it, and everything
    else in this file depends on that convention holding. }
  if PInt64(AutoBase[idx])^ <> Int64(PtrUInt(AutoBase[idx])) then Inc(Errs[idx]);
  { the stub zeroes the block; a reused stack must not show the previous
    thread's slots. }
  if TlsSlot(15)^ <> 0 then Inc(Errs[idx]);
  tag := 2000 + idx;
  TlsSlot(15)^ := tag;
  for k := 1 to CHURN do
    if TlsSlot(15)^ <> tag then Inc(Errs[idx]);
  if TlsSlot(15)^ <> tag then Inc(Errs[idx]);
end;

{ Phase B: install our own block over the stub's. }
procedure Body(arg: Pointer);
var idx, k: Integer; tag: Int64;
begin
  idx := Integer(PtrUInt(arg));
  InstallTls(@Blocks[idx][0]);
  tag := 1000 + idx;
  TlsSlot(15)^ := tag;
  for k := 1 to CHURN do
    if TlsSlot(15)^ <> tag then Inc(Errs[idx]);
  { the self-pointer convention itself }
  if __pxxTlsBase <> Pointer(@Blocks[idx][0]) then Inc(Errs[idx]);
end;

var mb: Pointer; ignoreI: Integer;
begin
  { ---- phase 0: the MAIN thread, which installs nothing ---- }
  { It passes through no clone stub, and a static pxx binary starts with fs base
    0, so before feature-a-tls-block-for-the-main-thread this faulted outright.
    The block comes from BSS via code at the ELF entry point, so this holds on
    every frontend and in every mode, not just --threadsafe. }
  errors := 0;
  mb := __pxxTlsBase;
  if mb = nil then Inc(errors);
  if PInt64(mb)^ <> Int64(PtrUInt(mb)) then Inc(errors);   { slot 0 = self }
  { slots 12..15 zero. Slots 1..3 are the I/O lock's business, 4..7 the signal
    stub's and 8..11 the exception runtime's, and the ENTRY CODE fills 1..3
    (tid, stack low, stack high), so asserting they are zero here is asserting
    the opposite of the contract -- which is how this loop failed the day the
    bounds landed, and it has earned its keep three more times since. }
  for i := 12 to 15 do
    if PInt64(PtrUInt(mb) + PtrUInt(i * 8))^ <> 0 then Inc(errors);

  { and the manual path still works, over the top of that block }
  { Installing our own block over the entry one leaves slots 1..3 zero, so every
    Writeln below falls back to gettid instead of trusting a block whose bounds
    nobody filled. That is the fail-safe direction, and this line exercises it. }
  InstallTls(@Blocks[NTHREADS][0]);
  TlsSlot(15)^ := 999;

  { ---- phase A: the clone stub's automatic install ---- }
  GoA := 0;
  for i := 0 to NTHREADS - 1 do
    begin Errs[i] := 0; AutoBase[i] := nil; BarrierLate[i] := 0; end;
  for i := 0 to NTHREADS - 1 do
    if PalThreadCreate(Handles[i], @AutoBody, Pointer(PtrUInt(i)), 0) <> 0 then
    begin
      Writeln('spawn failed');
      Halt(1);
    end;
  { EVERY CHILD NOW EXISTS -- PalThreadCreate blocks on the child's own
    identity-published handshake -- AND NONE OF THEM CAN HAVE EXITED, because
    each is parked in WaitForGo. Releasing them here is therefore the instant at
    which all NTHREADS are provably alive at once, which is the precondition the
    distinctness check further down needs and never used to state. }
  GoA := 1;
  ignoreI := PalFutexWake(@GoA, NTHREADS);
  for i := 0 to NTHREADS - 1 do PalThreadJoin(Handles[i]);

  for i := 0 to NTHREADS - 1 do Inc(errors, Errs[i]);
  { A child that gave up waiting means the overlap was never established, so
    the comparison below is measuring something else. Counted as an error
    rather than skipped: skipping it would make an unestablished precondition
    print `errors=0`. }
  for i := 0 to NTHREADS - 1 do Inc(errors, BarrierLate[i]);
  { distinct blocks -- the aliasing bug this whole ticket is about. Also
    distinct from the main thread's, which no clone stub touched. }
  for i := 0 to NTHREADS - 1 do
  begin
    if AutoBase[i] = nil then Inc(errors);
    if AutoBase[i] = Pointer(@Blocks[NTHREADS][0]) then Inc(errors);
    for j := 0 to NTHREADS - 1 do
      if (i <> j) and (AutoBase[i] = AutoBase[j]) then Inc(errors);
  end;
  if TlsSlot(15)^ <> 999 then Inc(errors);   { four children later, ours is ours }

  { ---- phase A2: the block a RECYCLED stack hands back ---- }
  { The stub carves its block off the top of the child's stack, and that stack
    is given back: PalThreadJoin munmaps it, and ReapSweep -- which
    PalThreadCreate runs once per call -- munmaps the stack of any thread the
    kernel has confirmed dead. Linux then hands the same address straight back
    to the next mmap of the same size, so A THREAD CREATED AFTER AN EARLIER ONE
    EXITED GETS THE SAME TLS BASE. That is correct, it is the point of the
    reclaim, and it is what phase A's distinctness check must not be read as
    forbidding -- distinctness is a statement about threads that are alive AT
    THE SAME TIME, which is why phase A now holds its four open.

    What must hold for a recycled block is that the stub re-zeroes it and
    re-writes its self-pointer, and AutoBody already asserts both. So this phase
    is the same body run SERIALLY, create-join-create-join, to reach the
    recycled-block path on purpose instead of reaching it about 7% of the time
    by luck -- which is what used to happen, and it was the luck, not the path,
    that reddened the tier.

    DELIBERATELY NOT ASSERTED: that the address actually came back. It does,
    200/200 runs of a six-thread serial probe on this host, but that is a
    statement about one kernel's mmap policy and pinning it here would be a
    host-dependent control -- a guard that reddens on a working runtime
    somewhere else. A host that hands out fresh addresses simply exercises
    fresh blocks here and the checks still hold. What would retire that caution
    is a way to ask for a specific stack address, which PalThreadCreate has no
    parameter for. }
  { Set the release word HERE rather than inheriting phase A's. A2 wants its
    threads serialised, so it must not depend on a previous phase having left
    the word set: that coupling is what makes one passing part of a run supply
    what another part needs, and it costs 5s per thread when phase A is the
    part that failed. }
  GoA := 1;
  for i := 0 to NTHREADS - 1 do begin Errs[i] := 0; AutoBase[i] := nil; end;
  for i := 0 to NTHREADS - 1 do
  begin
    if PalThreadCreate(Handles[i], @AutoBody, Pointer(PtrUInt(i)), 0) <> 0 then
    begin
      Writeln('spawn failed');
      Halt(1);
    end;
    PalThreadJoin(Handles[i]);
  end;
  for i := 0 to NTHREADS - 1 do Inc(errors, Errs[i]);
  for i := 0 to NTHREADS - 1 do
    if AutoBase[i] = nil then Inc(errors);
  if TlsSlot(15)^ <> 999 then Inc(errors);   { and ours is still ours }

  { ---- phase B: a thread installing its own block over the stub's ---- }
  for i := 0 to NTHREADS - 1 do Errs[i] := 0;
  for i := 0 to NTHREADS - 1 do
    if PalThreadCreate(Handles[i], @Body, Pointer(PtrUInt(i)), 0) <> 0 then
    begin
      Writeln('spawn failed');
      Halt(1);
    end;
  for i := 0 to NTHREADS - 1 do PalThreadJoin(Handles[i]);

  for i := 0 to NTHREADS - 1 do Inc(errors, Errs[i]);
  for i := 0 to NTHREADS - 1 do
    if Blocks[i][15] <> 1000 + i then Inc(errors);
  { the parent's own base survived four children installing theirs }
  if TlsSlot(15)^ <> 999 then Inc(errors);
  if __pxxTlsBase <> Pointer(@Blocks[NTHREADS][0]) then Inc(errors);

  Writeln('errors=', errors);
  if errors = 0 then Writeln('TLS OK');
end.
