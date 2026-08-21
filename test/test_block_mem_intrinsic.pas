program test_block_mem_intrinsic;
{ __pxxblockmove(dest, src, n) / __pxxblockfill(dest, n, byteval) -- the inline
  bulk-memory intrinsics behind Move/FillChar on x86-64 (IR_BLOCK_MEM, `rep
  movsb` / `rep stosb`).

  What the intrinsic promises and this test pins:
   - it copies/fills exactly n bytes and not one more, at any alignment;
   - a count of 0 or a NEGATIVE count touches nothing (the count reaches rcx,
     where a sign-extended -1 would ask for four billion bytes);
   - it returns dest, so it can stand in an expression statement even though
     `rep` has advanced rdi by then;
   - the move is FORWARD only -- a destination below an overlapping source is
     fine, which is the direction Move's own caller-side check leaves for it.
  feature-move-fillchar-intrinsics }
const
  BUFN = 512;
var
  a: array[0..BUFN - 1] of Byte;
  base: Int64;
  ok, total, i, k, dof, sof, n, guard: Longint;
  r: Int64;

procedure Check(const what: AnsiString; good: Boolean);
begin
  total := total + 1;
  if good then ok := ok + 1 else writeln('FAIL ', what);
end;

begin
  ok := 0; total := 0;
  base := Int64(@a[0]);

  { copy exactly n bytes, every alignment pair, with a poisoned frame either side }
  for sof := 0 to 8 do
    for dof := 0 to 8 do
      for n := 0 to 33 do
      begin
        for i := 0 to BUFN - 1 do a[i] := 200;
        for i := 0 to 63 do a[i] := Byte((i * 5 + 1) and 255);
        r := __pxxblockmove(base + 256 + dof, base + sof, Int64(n));
        guard := 0;
        for i := 0 to n - 1 do
          if a[256 + dof + i] <> a[sof + i] then guard := guard + 1;
        if (256 + dof > 0) and (a[256 + dof - 1] <> 200) then guard := guard + 1;
        if a[256 + dof + n] <> 200 then guard := guard + 1;
        if r <> base + 256 + dof then guard := guard + 1;
        Check('blockmove', guard = 0);
      end;

  { overlapping, destination BELOW the source: forward copy is the right answer }
  for sof := 1 to 8 do
    for n := 0 to 33 do
    begin
      for i := 0 to BUFN - 1 do a[i] := Byte((i * 7 + 3) and 255);
      r := __pxxblockmove(base + 100, base + 100 + sof, Int64(n));
      guard := 0;
      for i := 0 to n - 1 do
        if a[100 + i] <> Byte(((100 + sof + i) * 7 + 3) and 255) then guard := guard + 1;
      Check('blockmove-overlap-down', guard = 0);
    end;

  { fill exactly n bytes, every alignment, value and guards checked }
  for dof := 0 to 8 do
    for n := 0 to 33 do
      for k := 0 to 3 do
      begin
        for i := 0 to BUFN - 1 do a[i] := 200;
        r := __pxxblockfill(base + 300 + dof, Int64(n), Int64(k * 85));
        guard := 0;
        for i := 0 to n - 1 do
          if a[300 + dof + i] <> Byte(k * 85) then guard := guard + 1;
        if (dof > 0) and (a[300 + dof - 1] <> 200) then guard := guard + 1;
        if a[300 + dof + n] <> 200 then guard := guard + 1;
        if r <> base + 300 + dof then guard := guard + 1;
        Check('blockfill', guard = 0);
      end;

  { zero and negative counts must not write a single byte }
  for i := 0 to BUFN - 1 do a[i] := 42;
  r := __pxxblockmove(base + 8, base, 0);
  r := __pxxblockmove(base + 8, base, -1);
  r := __pxxblockfill(base + 8, 0, 7);
  r := __pxxblockfill(base + 8, -1, 7);
  r := __pxxblockfill(base + 8, -1000000, 7);
  guard := 0;
  for i := 0 to BUFN - 1 do if a[i] <> 42 then guard := guard + 1;
  Check('empty-and-negative-counts', guard = 0);

  { a big one, past anything a loop-unroll boundary could hide }
  for i := 0 to BUFN - 1 do a[i] := Byte(i and 255);
  r := __pxxblockmove(base + 256, base, 256);
  guard := 0;
  for i := 0 to 255 do if a[256 + i] <> Byte(i and 255) then guard := guard + 1;
  Check('bulk-256', guard = 0);

  writeln('total ok ', ok, ' / ', total);
end.
