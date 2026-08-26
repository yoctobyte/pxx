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

  NOT covered: a pointer to a named DYNAMIC array (`PDyn = ^TDyn`), whose
  Length/High still answer 1 and 0
  (bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one); and a FORWARD
  `PA = ^TA` written ahead of TA's own declaration, which cannot see an ArrType
  entry that does not exist yet.

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

var
  w: TW;  qw: PW;
  l: TL;  ql: PL;
  o: TOne; qo: POne;
  ra: TRA; qra: PRA;
  g: TG;  qg: PG;
  n: TN;  qn: PN;
  i, j: Integer;
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


  { writing THROUGH the pointer lands where the variable can see it }
  qw^[2] := 42; qra^[1].c := 77;
  WriteLn('write  : ', w[2], ' ', ra[1].c);
end.
