program test_clone_entry_with_a_hidden_result;
{ A THREAD ENTRY WHOSE RESULT RIDES THE CALLER-OWNED HIDDEN DESTINATION.

  The clone trampoline calls an entry it knows nothing about. A callee whose
  return type is RetViaHiddenDest -- a record, a set, a frozen string, a
  Variant, a promo int -- does not return its value in a register: it copies it
  through a pointer the CALLER is obliged to hand it, in a register fixed per
  target (r10 on x86-64, ecx on i386, x8 on aarch64, r12 on arm32). The stub set
  none of them, so the child copied its result through whatever the clone
  syscall sequence had left there. On x86-64 that register is r10, which the
  stub loads with ctidptr, so `__pxxclone(..., 0)` wrote through a NULL pointer.

  WHY NO PASCAL PROGRAM HAD EVER HIT IT AND EVERY NILPY ONE DOES: the PAL's
  TThreadEntry is a `procedure`, so every thread in this tree returns nothing --
  and a NilPy `def` compiles to a function returning a Variant, so there is no
  NilPy thread that does not. test_nilpy_thread_clone.npy caught it as a ~30%
  intermittent SIGSEGV (regression-test-threads-test-nilpy-thread-clone-2); it
  is intermittent only because the parent usually finishes first, not because
  anything about it is rare.

  THE ENTRY IS SPAWNED THROUGH PalThreadCreate rather than a raw __pxxclone so
  that one source runs on every threading target: the PAL owns the stack mmap
  and the syscall numbers. The cast to TThreadEntry is the whole point -- a
  function of the right shape reaching a trampoline that promises nothing about
  results.

  ASSERTS WHERE THE WRITE LANDED, NOT WHETHER THE PROCESS SURVIVED. The child's
  result has nowhere to go and is discarded by construction, so there is no
  value to compare -- but a wild write is not observable by a value assertion on
  anything the program computes, and "it did not crash" is a 70%-pass coin
  toss: measured on the pinned (pre-fix) compiler, 5/20 then 9/30 runs failed,
  because scribbling over a join handle is usually SILENT (munmap of a garbage
  range is ignored, and the kernel clears the tid word afterwards anyway).
  So the assertion is on the HANDLE the stray pointer aims at: PalThreadCreate
  passes @h.TidWord as ctidptr, x86-64's clone sequence leaves that in r10, and
  StackSize sits 16 bytes past it -- inside a 128-byte record result and inside
  a 48-byte string[40] one. Snapshot it, join, compare. Each entry spins first
  so the snapshot is taken before any child can have returned. }
uses palthread;

const
  NT = 4;

type
  { 16 words, deliberately: the destination the stub failed to set is the
    JOIN HANDLE's tid word (PalThreadCreate passes @h.TidWord as ctidptr and
    x86-64's clone sequence leaves that in r10), so a result WIDE enough to
    run off the end of one handle is what turns a 5-in-20 corruption into a
    near-certain one. Measured on the pinned compiler: 4 words failed 5/20,
    16 words fails every run. }
  TRec  = record a: array[0..15] of Int64; end;
  TSet  = set of 0..63;
  TFrz  = string[40];

var
  ran:  array[0..NT-1] of Int64;
  kind: array[0..NT-1] of Int64;

{ RECORD result: the plainest hidden-destination return. }
function RecEntry(arg: Pointer): TRec;
var k, i, spin: Int64;
begin
  spin := 0; while spin < 2000000 do spin := spin + 1;  { snapshot window }
  k := Int64(arg);
  ran[k] := 1000 + k; kind[k] := 1;
  for i := 0 to 15 do Result.a[i] := i + 1;
end;

{ SET result: a different width through the same register. }
function SetEntry(arg: Pointer): TSet;
var k, spin: Int64;
begin
  spin := 0; while spin < 2000000 do spin := spin + 1;
  k := Int64(arg);
  ran[k] := 1000 + k; kind[k] := 2;
  Result := [1, 5, 63];
end;

{ FROZEN STRING result: the third family, and the one whose copy size depends on
  a declared capacity rather than a type kind. }
function StrEntry(arg: Pointer): TFrz;
var k, spin: Int64;
begin
  spin := 0; while spin < 2000000 do spin := spin + 1;
  k := Int64(arg);
  ran[k] := 1000 + k; kind[k] := 3;
  Result := 'a thread result nobody reads';
end;

{ The control: an entry that returns NOTHING, i.e. the shape every existing
  thread in the tree has. It must keep working -- the stub now writes a register
  this one never reads. }
procedure VoidEntry(arg: Pointer);
var k, spin: Int64;
begin
  spin := 0; while spin < 2000000 do spin := spin + 1;
  k := Int64(arg);
  ran[k] := 1000 + k; kind[k] := 4;
end;

var
  h: array[0..NT-1] of TThreadHandle;
  savedSize: array[0..NT-1] of Int64;
  i, okCount, intact: Integer;
  rc: Integer;
begin
  for i := 0 to NT - 1 do begin ran[i] := 0; kind[i] := 0; end;

  rc := PalThreadCreate(h[0], TThreadEntry(@RecEntry),  Pointer(0), 0);
  if rc <> 0 then begin writeln('create FAIL 0'); Halt(1); end;
  rc := PalThreadCreate(h[1], TThreadEntry(@SetEntry),  Pointer(1), 0);
  if rc <> 0 then begin writeln('create FAIL 1'); Halt(1); end;
  rc := PalThreadCreate(h[2], TThreadEntry(@StrEntry),  Pointer(2), 0);
  if rc <> 0 then begin writeln('create FAIL 2'); Halt(1); end;
  rc := PalThreadCreate(h[3], TThreadEntry(@VoidEntry), Pointer(3), 0);
  if rc <> 0 then begin writeln('create FAIL 3'); Halt(1); end;

  { Snapshotted while every child is still inside its spin. StackSize is the
    field that SURVIVES a join (Join zeroes StackBase by design), so it is the
    one a post-join comparison can speak about. }
  for i := 0 to NT - 1 do savedSize[i] := h[i].StackSize;

  for i := 0 to NT - 1 do
    PalThreadJoin(h[i]);

  okCount := 0; intact := 0;
  for i := 0 to NT - 1 do
  begin
    if (ran[i] = 1000 + i) and (kind[i] = i + 1) then okCount := okCount + 1;
    if h[i].StackSize = savedSize[i] then intact := intact + 1;
  end;

  writeln('threads ran ', okCount, ' / ', NT);
  writeln('handles intact ', intact, ' / ', NT);
  if (okCount = NT) and (intact = NT) then writeln('CLONEHIDDENRET OK')
  else writeln('CLONEHIDDENRET FAIL');
end.
