program test_heap_alloc_zeroed;
{ PXXAlloc's contract is that it hands back a ZEROED payload on every path, and
  x86-64's inline SetLength lowering now DEPENDS on it instead of re-zeroing
  behind it (feature-opt-heap-per-thread-cache). That dependency is invisible at
  the call site, so this file is its guard. NATIVE ONLY: the cross backends go
  through PXXDynSetLen/PXXStrSetLen, which still zero a second time, so this
  test cannot fail there -- see the Makefile note.

  The sizes are not arbitrary: zeroing picks its instruction at two measured
  thresholds -- MEMZERO_REP_MIN = 48 inside PXXMemZero, HEAP_ZERO_INLINE_MAX =
  64 in PXXAlloc -- so every element count below straddles one of them, counted
  in BYTES of the allocated block (16-byte header + 4 per LongInt).

  NON-VACUOUS BY CONSTRUCTION: every array is filled with $FF and freed BEFORE
  it is reallocated, so the block comes back off its size bin holding the
  previous contents. Drop either zeroing arm and this prints a nonzero sum. }
var
  b: array of LongInt;
  s: AnsiString;
  i, k, n, rep, bad: LongInt;
  sizes: array[0..9] of LongInt;
begin
  sizes[0] := 2;    { 24 B  -- inline loop, under both thresholds }
  sizes[1] := 4;    { 32 B }
  sizes[2] := 6;    { 40 B }
  sizes[3] := 8;    { 48 B  -- exactly MEMZERO_REP_MIN }
  sizes[4] := 10;   { 56 B }
  sizes[5] := 12;   { 64 B  -- exactly HEAP_ZERO_INLINE_MAX }
  sizes[6] := 14;   { 72 B  -- first size PXXAlloc delegates }
  sizes[7] := 28;   { 128 B }
  sizes[8] := 124;  { 512 B -- last size with its own bin }
  sizes[9] := 252;  { 1024 B -- above HEAP_BIN_MAX, the first-fit path }

  bad := 0;
  for k := 0 to 9 do
  begin
    n := sizes[k];
    for rep := 1 to 3 do
    begin
      { poison, then release it back to its bin }
      b := nil;
      SetLength(b, n);
      for i := 0 to n - 1 do b[i] := -1;
      b := nil;
      { and take it straight back }
      SetLength(b, n);
      for i := 0 to n - 1 do
        if b[i] <> 0 then bad := bad + 1;
    end;
  end;
  WriteLn('dynarray nonzero: ', bad);

  { the same for a managed string, whose growth region PXXStrSetLen also stopped
    re-zeroing; lengths are deliberately NOT multiples of the machine word, so
    PXXMemZero's byte tail is on the hook too }
  bad := 0;
  for k := 1 to 200 do
  begin
    s := '';
    SetLength(s, k);
    for i := 1 to k do s[i] := #255;
    s := '';
    SetLength(s, k);
    for i := 1 to k do
      if s[i] <> #0 then bad := bad + 1;
  end;
  WriteLn('string nonzero: ', bad);
end.
