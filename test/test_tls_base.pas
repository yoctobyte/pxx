program test_tls_base;
{ __pxxTlsBase: a per-thread slot that is genuinely distinct per thread, reachable
  without a syscall (feature-a-thread-local-storage-via-clone-settls).

  The ticket's premise was that PXX_CLONE_THREAD omits CLONE_SETTLS, so every
  thread inherits the parent's fs base and an fs:-relative slot silently aliases.
  That observation is true; the prescribed remedy -- pass a tls argument through
  clone -- is not the smallest one. arch_prctl(ARCH_SET_FS) works on the CALLING
  thread, so a thread can install its own block as its first act, and the whole
  fix is one read-side intrinsic instead of a sixth __pxxclone argument plus four
  backend changes.

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
  ARCH_SET_FS    = $1002;
  NTHREADS       = 4;
  CHURN          = 20000;

type
  PInt64 = ^Int64;
  { 8 slots. Slot 0 is the block's own address (the convention __pxxTlsBase
    reads through); slot 1 is this test's per-thread tag. }
  TTlsBlock = array[0..7] of Int64;

var
  Blocks: array[0..NTHREADS] of TTlsBlock;   { [NTHREADS] is the main thread's }
  Handles: array[0..NTHREADS - 1] of TThreadHandle;
  Errs: array[0..NTHREADS - 1] of Integer;
  i, errors: Integer;

{ Make block b the calling thread's TLS block. }
procedure InstallTls(b: PInt64);
var r: Int64;
begin
  b^ := Int64(PtrUInt(b));   { slot 0 = self, so fs:[0] yields the base }
  r := __pxxrawsyscall(SYS_arch_prctl, ARCH_SET_FS, Int64(PtrUInt(b)), 0, 0, 0, 0);
  if r <> 0 then
  begin
    Writeln('arch_prctl failed: ', r);
    Halt(1);
  end;
end;

function TlsSlot(n: Integer): PInt64;
begin
  TlsSlot := PInt64(PtrUInt(__pxxTlsBase) + PtrUInt(n * 8));
end;

procedure Body(arg: Pointer);
var idx, k: Integer; tag: Int64;
begin
  idx := Integer(PtrUInt(arg));
  InstallTls(@Blocks[idx][0]);
  tag := 1000 + idx;
  TlsSlot(1)^ := tag;
  for k := 1 to CHURN do
    if TlsSlot(1)^ <> tag then Inc(Errs[idx]);
  { the self-pointer convention itself }
  if __pxxTlsBase <> Pointer(@Blocks[idx][0]) then Inc(Errs[idx]);
end;

begin
  InstallTls(@Blocks[NTHREADS][0]);
  TlsSlot(1)^ := 999;

  for i := 0 to NTHREADS - 1 do Errs[i] := 0;
  for i := 0 to NTHREADS - 1 do
    if PalThreadCreate(Handles[i], @Body, Pointer(PtrUInt(i)), 0) <> 0 then
    begin
      Writeln('spawn failed');
      Halt(1);
    end;
  for i := 0 to NTHREADS - 1 do PalThreadJoin(Handles[i]);

  errors := 0;
  for i := 0 to NTHREADS - 1 do Inc(errors, Errs[i]);
  for i := 0 to NTHREADS - 1 do
    if Blocks[i][1] <> 1000 + i then Inc(errors);
  { the parent's own base survived four children installing theirs }
  if TlsSlot(1)^ <> 999 then Inc(errors);
  if __pxxTlsBase <> Pointer(@Blocks[NTHREADS][0]) then Inc(errors);

  Writeln('errors=', errors);
  if errors = 0 then Writeln('TLS OK');
end.
