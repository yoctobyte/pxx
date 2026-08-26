program test_pointer_to_a_named_fixed_array;
{ `PFixed = ^TFixed` where TFixed is a named FIXED-array type. An array alias is
  not in the scalar alias table, so ParseTypeKind fell through its unknown-name
  default and recorded the pointee as tyInteger. Everything downstream inherited
  a 4-byte stride and no element record:

    p^[i] over `array[0..3] of Int64`   read halves of the wrong elements
    p^[i].b over an array of records    resolved EVERY field at offset 0
    Length(p^)                          0   (fpc: the extent)
    High(p^)                            -1  (fpc: the upper bound)
    SizeOf(p^)                          the ELEMENT size, not the aggregate's

  all silently, exit 0 — while `p^[0]` of a LongWord array happened to be right,
  because that element is 4 bytes wide.

  The pointee's extent now lives in SymPtrElemArrLen, the slot the C frontend
  already used for `elem (*p)[N]` — one concept, one slot — with the low bound in
  the pointer symbol's otherwise-unused SymArrDimLo row.

  A MULTI-DIM pointee is covered as of 2026-08-26: `qg^[i, j]` used to flatten
  with the wrong dims (`0 1 2 1 2 10` for a 2x3 where fpc prints `0 1 2 10 11
  12`) and Length answered the flattened 6 where fpc answers the first
  dimension's 2. NodeArrNDInfo now accepts a deref base, and DerefPtrArrayInfo
  reports the first-dim span and the flat count SEPARATELY — Length/High/Low
  take the former, SizeOf the latter, which is the same split the
  plain-variable arms beside them already make.
  bug-p-a-pointer-to-a-multidim-array-indexes-and-measures-the-flat-extent

  A pointer to a named DYNAMIC array is covered as of 2026-08-26. Its extent is
  not a compile-time constant, so it does NOT go through the fixed-array slot —
  it never should have: ArrTypeLo/Hi are never written for a dyn alias, and
  reading them anyway computed an extent of exactly 1, which is where the old
  `Length(pdy^)` = 1 and `High(pdy^)` = 0 came from. Not a missing case; a
  confident wrong answer derived from two fields nobody had set.
  bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one

  NOT covered, and NOT a gap in this test: a pointer to a dyn array goes STALE
  when the array is reallocated, because `@dy` in pxx yields the HANDLE rather
  than the address of the dy variable. After `SetLength(dy, 9)` fpc's
  `Length(pdy^)` is 9 and ours is 5 — off the old buffer, which SetLength may
  already have freed. Deliberately not asserted here; that divergence is
  bug-p-address-of-a-dynamic-array-captures-the-handle-not-the-variable.

  Still NOT covered: a FORWARD `PA = ^TA` written ahead of TA's own declaration,
  which cannot see an ArrType entry that does not exist yet.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  TW    = array[0..3] of Int64;
  PW    = ^TW;
  TL    = array[0..3] of LongWord;
  PL    = ^TL;
  TOne  = array[1..4] of LongWord;   { non-zero low bound }
  POne  = ^TOne;
  TRec  = record a, b, c: LongWord; end;
  TRA   = array[0..2] of TRec;
  PRA   = ^TRA;
  TG    = array[0..1, 0..2] of LongWord;          { 2-D, zero lows }
  PG    = ^TG;
  TN    = array[1..2, 5..7] of LongWord;          { 2-D, non-zero lows on both }
  PN    = ^TN;
  TDyn  = array of LongWord;                      { DYNAMIC pointee — no extent }
  PDyn  = ^TDyn;
  TDStr = array of AnsiString;                    { ...with a MANAGED element }
  PDStr = ^TDStr;

var
  w: TW;  qw: PW;
  l: TL;  ql: PL;
  o: TOne; qo: POne;
  ra: TRA; qra: PRA;
  g: TG;  qg: PG;
  n: TN;  qn: PN;
  dy: TDyn; qdy: PDyn;
  ds: TDStr; qds: PDStr;
  i, j, k, tot: Integer;
  r: TRec;

begin
  for i := 0 to 3 do w[i] := 1000000000 + i;
  qw := @w;
  Write('int64  :');
  for i := 0 to 3 do Write(' ', qw^[i]);
  WriteLn(' | ', Length(qw^), ' ', Low(qw^), ' ', High(qw^), ' ', SizeOf(qw^));

  for i := 0 to 3 do l[i] := 10 + i;
  ql := @l;
  Write('lword  :');
  for i := 0 to 3 do Write(' ', ql^[i]);
  WriteLn(' | ', Length(ql^), ' ', Low(ql^), ' ', High(ql^), ' ', SizeOf(ql^));

  for i := 1 to 4 do o[i] := 100 + i;
  qo := @o;
  Write('lowbnd :');
  for i := Low(qo^) to High(qo^) do Write(' ', qo^[i]);
  WriteLn(' | ', Length(qo^), ' ', Low(qo^), ' ', High(qo^), ' ', SizeOf(qo^));

  for i := 0 to 2 do
  begin ra[i].a := i; ra[i].b := 10 + i; ra[i].c := 100 + i; end;
  qra := @ra;
  Write('record :');
  for i := 0 to 2 do Write(' ', qra^[i].a, '/', qra^[i].b, '/', qra^[i].c);
  WriteLn(' | ', Length(qra^), ' ', High(qra^), ' ', SizeOf(qra^));
  r := qra^[2];
  WriteLn('whole  : ', r.a, ' ', r.b, ' ', r.c);

  { 2-D pointee: comma syntax, bracket-chain syntax, and the whole-array
    measures. Length/High/Low answer the FIRST dimension; SizeOf the aggregate. }
  for i := 0 to 1 do for j := 0 to 2 do g[i, j] := i * 10 + j;
  qg := @g;
  Write('2d     :');
  for i := 0 to 1 do for j := 0 to 2 do Write(' ', qg^[i, j]);
  WriteLn(' | ', Length(qg^), ' ', Low(qg^), ' ', High(qg^), ' ', SizeOf(qg^));
  Write('2d brk :');
  for i := 0 to 1 do for j := 0 to 2 do Write(' ', qg^[i][j]);
  WriteLn;

  { ...and with a non-zero low bound on BOTH dims, which is what separates a
    correct flatten from one that subtracts the low bound twice. }
  for i := 1 to 2 do for j := 5 to 7 do n[i, j] := i * 100 + j;
  qn := @n;
  Write('2d lowb:');
  for i := 1 to 2 do for j := 5 to 7 do Write(' ', qn^[i, j]);
  WriteLn(' | ', Length(qn^), ' ', Low(qn^), ' ', High(qn^), ' ', SizeOf(qn^));


  { A DYNAMIC pointee: the extent is a runtime read of the handle's [-8] header,
    not a fold. Called in a loop because the hidden dyn-array temp the lowering
    binds the handle to holds it BORROWED — if it ever owned it, the first
    finalize would free the array and every later read would be a use-after-free. }
  SetLength(dy, 5);
  for i := 0 to 4 do dy[i] := i * 3;
  qdy := @dy;
  tot := 0;
  for k := 1 to 200 do tot := tot + Length(qdy^);
  Write('dyn    :');
  for i := 0 to 4 do Write(' ', qdy^[i]);
  WriteLn(' | ', Length(qdy^), ' ', Low(qdy^), ' ', High(qdy^), ' tot=', tot);
  Write('dyn intact:');
  for i := 0 to 4 do Write(' ', dy[i]);
  WriteLn(' | ', Length(dy));

  { a MANAGED element type is the harsher ownership case — a wrong free here
    drops refcounts and the strings come back as garbage }
  SetLength(ds, 3);
  ds[0] := 'alpha'; ds[1] := 'beta'; ds[2] := 'gamma';
  qds := @ds;
  for k := 1 to 200 do tot := tot + Length(qds^);
  WriteLn('dynstr : ', ds[0], ' ', ds[1], ' ', ds[2], ' | ',
          Length(qds^), ' ', High(qds^));

  { writing THROUGH the pointer lands where the variable can see it }
  qw^[2] := 42; qra^[1].c := 77;
  WriteLn('write  : ', w[2], ' ', ra[1].c);
end.
