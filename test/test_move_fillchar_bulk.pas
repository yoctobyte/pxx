program test_move_fillchar_bulk;
{ Move/FillChar over the whole alignment x size x overlap-direction grid.

  The bulk paths copy a machine word at a time, so every interesting case is a
  boundary one: a source and a destination that disagree modulo the word size,
  a count with a partial word at the end, and -- the case a forward-only copy
  gets wrong -- a destination that overlaps the source from above, where the
  copy has to run backward. A word-at-a-time backward loop lands on its own set
  of misaligned addresses, which is why the grid runs both directions.

  Oracle is a naive byte loop written out below rather than a recorded hash:
  the property under test is "the fast path agrees with the obvious one", and
  a hash only records what we happened to produce the day it was baked.
  feature-move-fillchar-intrinsics }
const
  BUFN = 256;
var
  a, b: array[0..BUFN - 1] of Byte;
  ok, total: Longint;

procedure Seed;
var i: Longint;
begin
  for i := 0 to BUFN - 1 do
  begin
    a[i] := Byte((i * 7 + 3) and 255);
    b[i] := a[i];
  end;
end;

{ Reference memmove on b[]: overlap-safe, one byte at a time. }
procedure RefMove(dst, src, n: Longint);
var i: Longint;
begin
  if n <= 0 then Exit;
  if (dst > src) and (dst < src + n) then
    for i := n - 1 downto 0 do b[dst + i] := b[src + i]
  else
    for i := 0 to n - 1 do b[dst + i] := b[src + i];
end;

procedure RefFill(dst, n: Longint; v: Byte);
var i: Longint;
begin
  for i := 0 to n - 1 do b[dst + i] := v;
end;

procedure Same(const what: AnsiString; dst, src, n: Longint);
var i, bad: Longint;
begin
  total := total + 1;
  bad := -1;
  for i := 0 to BUFN - 1 do
    if (a[i] <> b[i]) and (bad < 0) then bad := i;
  if bad < 0 then ok := ok + 1
  else
    writeln('FAIL ', what, ' dst=', dst, ' src=', src, ' n=', n,
            ' first diff at ', bad, ': got ', a[bad], ' want ', b[bad]);
end;

var
  so, dof, n, v, i, k: Longint;
begin
  ok := 0; total := 0;

  { non-overlapping, every (src mod 8, dst mod 8) pair and every tail length }
  for so := 0 to 8 do
    for dof := 0 to 8 do
      for n := 0 to 33 do
      begin
        Seed;
        Move(a[so], a[100 + dof], n);
        RefMove(100 + dof, so, n);
        Same('disjoint', 100 + dof, so, n);
      end;

  { overlapping, destination ABOVE the source -- must copy backward }
  for so := 0 to 8 do
    for dof := 1 to 8 do
      for n := 0 to 33 do
      begin
        Seed;
        Move(a[so], a[so + dof], n);
        RefMove(so + dof, so, n);
        Same('overlap-up', so + dof, so, n);
      end;

  { overlapping, destination BELOW the source -- forward is correct }
  for so := 0 to 8 do
    for dof := 1 to 8 do
      for n := 0 to 33 do
      begin
        Seed;
        Move(a[128 + so + dof], a[128 + so], n);
        RefMove(128 + so, 128 + so + dof, n);
        Same('overlap-down', 128 + so, 128 + so + dof, n);
      end;

  { a size well past one word, at both alignments }
  for dof := 0 to 8 do
  begin
    Seed;
    Move(a[0], a[dof], 200 - dof);
    RefMove(dof, 0, 200 - dof);
    Same('bulk', dof, 0, 200 - dof);
  end;

  { FillChar over the same grid }
  for dof := 0 to 8 do
    for n := 0 to 33 do
      for v := 0 to 3 do
      begin
        Seed;
        FillChar(a[dof], n, Byte(v * 85));
        RefFill(dof, n, Byte(v * 85));
        Same('fill', dof, -1, n);
      end;

  { zero and negative counts touch nothing }
  Seed;
  Move(a[0], a[10], 0);
  FillChar(a[0], 0, 1);
  FillChar(a[0], -5, 1);
  Same('empty', 0, 0, 0);

  { the word-splat must not leak past the count }
  Seed;
  for i := 0 to BUFN - 1 do a[i] := 0;
  for i := 0 to BUFN - 1 do b[i] := 0;
  FillChar(a[3], 17, 255);
  RefFill(3, 17, 255);
  Same('no-spill', 3, -1, 17);
  k := 0;
  for i := 0 to BUFN - 1 do if a[i] = 255 then k := k + 1;
  total := total + 1;
  if k = 17 then ok := ok + 1 else writeln('FAIL no-spill count=', k);

  writeln('total ok ', ok, ' / ', total);
end.
