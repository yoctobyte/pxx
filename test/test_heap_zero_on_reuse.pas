program test_heap_zero_on_reuse;
{ PXXAlloc's zero-on-reuse contract, exercised through EVERY arm of its
  size dispatch. A block popped off a free bin (or off the large first-fit
  list) must come back all-zero, exactly like virgin arena memory, because
  callers -- managed refcount/length headers, zeroed instance slots -- state
  that precondition and no other.

  The three arms, and why the sizes are what they are:
    <= ALLOC_INLINE_ZERO_MAX (64 bytes)  TSmall  -- inline word loop
    >  that, <= HEAP_BIN_MAX  (512)      TBig    -- PXXMemZero (rep stosb on x86-64)
    >  HEAP_BIN_MAX                      THuge   -- the large first-fit list

  DO NOT rewrite this with dynamic arrays. The obvious `SetLength(b, N)`
  spelling CANNOT FAIL: SetLength zeroes the element span itself, so the test
  passes with PXXAlloc's zeroing removed entirely -- measured, all three arms
  deleted, still green. A class instance is the shape that actually observes
  the allocator's contract, because nothing zeroes the fields afterwards.
  Positive controls, each arm deleted in turn: 192 / 204 / 1536 dirty words. }
{$mode objfpc}{$H+}
type
  TSmall = class a: array[0..3]   of LongInt; end;   {   16 bytes }
  TBig   = class a: array[0..63]  of LongInt; end;   {  256 bytes }
  THuge  = class a: array[0..511] of LongInt; end;   { 2048 bytes }
var
  s: TSmall; b: TBig; h: THuge;
  pass, i, bad: LongInt;
begin
  bad := 0;
  { pass 1 dirties each block and frees it; passes 2..4 must find the SAME
    size class handed back clean off the free list }
  for pass := 1 to 4 do
  begin
    s := TSmall.Create;
    for i := 0 to 3   do if s.a[i] <> 0 then bad := bad + 1;
    for i := 0 to 3   do s.a[i] := -1431655766;
    s.Free;

    b := TBig.Create;
    for i := 0 to 63  do if b.a[i] <> 0 then bad := bad + 1;
    for i := 0 to 63  do b.a[i] := -1431655766;
    b.Free;

    h := THuge.Create;
    for i := 0 to 511 do if h.a[i] <> 0 then bad := bad + 1;
    for i := 0 to 511 do h.a[i] := -1431655766;
    h.Free;
  end;
  WriteLn('HEAP ZERO ON REUSE OK dirty=', bad);
end.
