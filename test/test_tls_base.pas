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

uses palthread;

const
  SYS_arch_prctl = 158;
  ARCH_SET_GS    = $1001;
  NTHREADS       = 4;
  CHURN          = 20000;

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

{ Phase A: use the block the CLONE STUB installed. No InstallTls here -- that is
  the whole assertion. }
procedure AutoBody(arg: Pointer);
var idx, k: Integer; tag: Int64;
begin
  idx := Integer(PtrUInt(arg));
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

var mb: Pointer;
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
  for i := 0 to NTHREADS - 1 do begin Errs[i] := 0; AutoBase[i] := nil; end;
  for i := 0 to NTHREADS - 1 do
    if PalThreadCreate(Handles[i], @AutoBody, Pointer(PtrUInt(i)), 0) <> 0 then
    begin
      Writeln('spawn failed');
      Halt(1);
    end;
  for i := 0 to NTHREADS - 1 do PalThreadJoin(Handles[i]);

  for i := 0 to NTHREADS - 1 do Inc(errors, Errs[i]);
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
