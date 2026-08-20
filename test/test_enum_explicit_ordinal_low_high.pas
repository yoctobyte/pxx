{ Low/High of an enum type answered 0 and count-1 -- the DECLARATION INDEX
  range -- instead of the range of the members' VALUES. Those coincide for a
  plain `(a, b, c)` and diverge the moment an explicit `= N` appears:

    TGap = (gX = 3, gY = 4, gZ = 9);
    Ord(Low(TGap))   was 0   FPC: 3     <- not even a value of the type
    Ord(High(TGap))  was 2   FPC: 9

  So `for g := Low(TGap) to High(TGap)` walked 0,1,2 -- three ordinals none of
  which is a TGap -- and stopped six short of gZ. Silent: every value printed,
  none of them right.

  The same 0..count-1 shorthand stood in for the ordinal range at four sites
  (both Low/High folders, the `set of <enum>` membership scan, and the
  array-index-type bound), so all four moved to one EnumTypeOrdRange helper.
  Every FPC-comparable expectation below is `fpc -O- -Mobjfpc`'s; the
  array[TGap] case is ours alone -- FPC refuses an enum with assignments as an
  array index type -- and is asserted for self-consistency. `set of TGap` FPC
  does accept, and it agrees.
  bug-p-low-high-of-an-enum-with-explicit-values-count-members }
program test_enum_explicit_ordinal_low_high;
{$mode objfpc}{$H+}

type
  TPlain = (pA, pB, pC);
  TGap   = (gX = 3, gY = 4, gZ = 9);
  TCol   = (cRed, cGreen = 5, cBlue, cGold = 20);
  TGapS  = set of TGap;

var
  ok, total, n, i: Integer;
  p: TPlain; g: TGap; c: TCol;
  gs: TGapS;
  ag: array[TGap] of Integer;

procedure Chk(const what: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;

  { the contiguous case -- unchanged, asserted so the fix cannot regress it }
  Chk('plain lo', Ord(Low(TPlain)), 0);
  Chk('plain hi', Ord(High(TPlain)), 2);
  n := 0;
  for p := Low(TPlain) to High(TPlain) do n := n + 1;
  Chk('plain loop', n, 3);

  { every member explicit, first one non-zero }
  Chk('gap lo', Ord(Low(TGap)), 3);
  Chk('gap hi', Ord(High(TGap)), 9);
  n := 0;
  for g := Low(TGap) to High(TGap) do n := n + 1;
  Chk('gap loop', n, 7);

  { a gap in the MIDDLE, and a member that continues from an explicit one }
  Chk('col lo', Ord(Low(TCol)), 0);
  Chk('col hi', Ord(High(TCol)), 20);
  Chk('col red', Ord(cRed), 0);
  Chk('col green', Ord(cGreen), 5);
  Chk('col blue', Ord(cBlue), 6);
  Chk('col gold', Ord(cGold), 20);
  n := 0;
  for c := Low(TCol) to High(TCol) do n := n + 1;
  Chk('col loop', n, 21);

  { a set whose element type has holes: the members live at bits 3, 4 and 9,
    so a scan bounded by the member COUNT never reached gZ }
  gs := [gX, gZ];
  Chk('in gX', Ord(gX in gs), 1);
  Chk('in gY', Ord(gY in gs), 0);
  Chk('in gZ', Ord(gZ in gs), 1);
  Include(gs, gY);
  Chk('after include', Ord(gY in gs), 1);
  Exclude(gs, gX);
  Chk('after exclude', Ord(gX in gs), 0);
  n := 0;
  for g in gs do n := n * 100 + Ord(g);
  Chk('for-in set', n, 409);

  { an array indexed by the holed enum spans its VALUE range, not its member
    count -- three slots could not hold an index of 9 }
  for g := Low(TGap) to High(TGap) do ag[g] := Ord(g) * 11;
  Chk('ag lo', ag[gX], 33);
  Chk('ag mid', ag[gY], 44);
  Chk('ag hi', ag[gZ], 99);
  Chk('ag len', SizeOf(ag) div SizeOf(Integer), 7);
  n := 0;
  for i := Ord(Low(TGap)) to Ord(High(TGap)) do n := n + ag[TGap(i)];
  Chk('ag sum', n, 11 * (3+4+5+6+7+8+9));

  writeln('total ok ', ok, ' / ', total);
end.
