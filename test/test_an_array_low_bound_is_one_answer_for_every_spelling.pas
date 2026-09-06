program test_an_array_low_bound_is_one_answer_for_every_spelling;
{ An array's low bound used to be answered by TWO mechanisms, and which one you
  got depended on how the CONTAINER WAS SPELLED. Measured with PXXDBG=a.ast over
  one `array[1..4]`, before the repair:

    x := a1[1]    ->  AN_INDEX(AN_IDENT, 1)      IR subtracted, from ConstVal
    x := p1^[1]   ->  AN_INDEX(AN_DEREF, 1 - 1)  the PARSER had subtracted

  Both were right. The defect was that "has the bound been applied yet?" was not
  a property of the node, so every new producer of an AN_INDEX had to know which
  convention its container followed -- and BuildForInArrayLoop, which synthesises
  its own, inherited neither and iterated shifted garbage.

  ArrayLoOf (ir.inc) now answers for every spelling and the subscript is always
  RAW. These rows assert the two spellings against EACH OTHER, so a change that
  shifts both identically cannot pass -- and against fpc, which agrees on all.

  THE N-D DEREF ROWS ARE NOT DECORATION. BuildFlatNDIndex subtracts every
  dimension's bound including dim 0, so a deref arm that answers for rank >= 2
  subtracts it twice. That shipped for the length of one build: `p^[1,1]` over
  array[1..3,1..3] read 0 instead of 11 and a 3-D pointee read 4310984. An
  N-D array SYMBOL cannot have the problem -- it carries ConstVal 0 and keeps
  bounds in the N-D dim table -- so the direct spelling stays green throughout
  and only the deref spelling discriminates.
  bug-a-an-array-low-bound-is-answered-by-two-mechanisms-and-a-deref-uses-the-other }
type
  TA   = array[1..4] of Integer;
  PA   = ^TA;
  TNeg = array[-2..2] of Integer;
  PNeg = ^TNeg;
  TM   = array[1..3, 1..3] of Integer;
  PM   = ^TM;
  TM3  = array[2..3, 1..2, 5..6] of Integer;
  PM3  = ^TM3;
  TRec = record c: array[5..7] of Integer; tail: Integer; end;
var
  a: TA; ptrA: PA;
  ng: TNeg; ptrNg: PNeg;
  m: TM; ptrM: PM;
  m3: TM3; ptrM3: PM3;
  r: TRec;
  i, j, k, fails: Integer;

procedure Chk(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;
  for i := 1 to 4 do a[i] := i * 11;
  ptrA := @a;
  for i := -2 to 2 do ng[i] := i * 100;
  ptrNg := @ng;
  for i := 1 to 3 do for j := 1 to 3 do m[i,j] := i * 10 + j;
  ptrM := @m;
  for i := 2 to 3 do for j := 1 to 2 do for k := 5 to 6 do
    m3[i,j,k] := i * 100 + j * 10 + k;
  ptrM3 := @m3;
  for i := 5 to 7 do r.c[i] := i * 3;
  r.tail := 42;

  { rank 1: ident, deref via variable, deref via INLINE CAST -- the third
    spelling is the one the deleted parser fold was originally added for. }
  Chk('ident lo1',      a[1],           11);
  Chk('ident lo4',      a[4],           44);
  Chk('deref lo1',      ptrA^[1],         11);
  Chk('deref lo4',      ptrA^[4],         44);
  Chk('cast  lo1',      PA(@a)^[1],     11);
  Chk('cast  lo4',      PA(@a)^[4],     44);

  { a NEGATIVE low bound, where an unsubtracted index reads before the array }
  Chk('ident neg-2',    ng[-2],        -200);
  Chk('deref neg-2',    ptrNg^[-2],      -200);
  Chk('deref neg2',     ptrNg^[2],        200);
  Chk('cast  neg-2',    PNeg(@ng)^[-2], -200);

  { a record FIELD array: the third spelling of the same question }
  Chk('field lo5',      r.c[5],          15);
  Chk('field lo7',      r.c[7],          21);
  Chk('field neighbour', r.tail,         42);

  { N-D through a deref: the rows that catch a double subtraction }
  Chk('nd ident 2,3',   m[2,3],          23);
  Chk('nd deref 2,3',   ptrM^[2,3],        23);
  Chk('nd deref 1,1',   ptrM^[1,1],        11);
  Chk('nd deref 3,3',   ptrM^[3,3],        33);
  Chk('nd3 ident',      m3[3,2,6],      326);
  Chk('nd3 deref hi',   ptrM3^[3,2,6],    326);
  Chk('nd3 deref lo',   ptrM3^[2,1,5],    215);

  { STORES, because a shifted write is silent and hits the neighbour }
  ptrA^[2] := 777;      Chk('store deref rank1',  a[2],     777);
  PA(@a)^[3] := 888;  Chk('store cast  rank1',  a[3],     888);
  Chk('store left lo4 alone',                   a[4],      44);
  ptrM^[2,2] := 999;    Chk('store deref nd',     m[2,2],   999);
  Chk('store left nd 3,3 alone',                m[3,3],    33);

  WriteLn('fails=', fails);
  WriteLn('ARRAYLO OK');
end.
