program test_symslot_stale_ndims;
{ bug-transitive-dns_cache-import-corrupts-managed-strings: AllocParam /
  AllocVar / AllocDynArray / AddConst did not reset SymArrNDims on a recycled
  symbol slot. Proc A's 2-D local leaves NDims=2 in its slot; proc B's 1-D
  named-array param lands on the same slot and (before the fix) indexed with
  the stale N-D dims — stride 64 instead of 4, silent data corruption. }
type
  TArr1 = array[0..15] of LongWord;
procedure UseND;
var m: array[0..3, 0..15] of Integer;
begin
  m[1, 2] := 7;
  if m[1, 2] <> 7 then writeln('nd-bad');
end;
function SumArr(const a: TArr1; n: Integer): LongWord;
var i: Integer; s: LongWord;
begin
  s := 0;
  for i := 0 to n - 1 do s := s + a[i];
  SumArr := s;
end;
var
  g: TArr1;
  i: Integer;
begin
  UseND;
  for i := 0 to 15 do g[i] := LongWord(i + 1);
  writeln(SumArr(g, 16));   { 1+2+...+16 = 136 }
end.
