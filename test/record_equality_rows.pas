{ Record `=` and `<>`, in the shapes that discriminate.

  EVERY ROW HERE ANSWERS THE SAME ON EVERY TARGET, because record equality is a
  language question and not a width one -- so this fixture carries a fixed
  expected block rather than a relation, and the recipe compares each target
  against the same text.

  THE ROWS THAT MEASURE ANYTHING ARE THE `tail` ONES: same first field,
  different last. Until 2026-09-07 the compiler compared ONE MACHINE WORD, so
  `same`, `firstdiff` and `bothdiff` were right by accident on x86-64, aarch64,
  arm32 and riscv32 -- a one-word compare and a real one agree on all three --
  and only a differing LAST field separates them. On i386 a record over 8 bytes
  is not in a register at all, so `same` answered F there: that row is this
  fixture's other discriminator and it points the opposite way.

  So the block below cannot pass on a compiler that does nothing: `flat tail`
  goes T on four targets and `flat same` goes F on the fifth. Verified against
  pin v407's binary, which fails both.
  bug-a-a-record-equality-compares-only-the-first-eight-bytes-on-every-target }
program record_equality_rows;
type
  TFlat  = record x, y: Int64; end;
  TInner = record p, q: Integer; end;
  TNest  = record h: Byte; inner: TInner; t: Int64; end;
  TStr   = record k: Integer; s: AnsiString; end;
  TFlt   = record a: Double; b: Single; end;
  TOuter = record tag: Integer; r: TFlat; end;
  PFlat  = ^TFlat;
  TElem  = record p, q: Integer; end;
  TArr   = record n: Integer; v: array[0..3] of Integer; end;
  T2D    = record m: array[0..2, 0..3] of Integer; end;
  TArec  = record e: array[0..2] of TElem; end;
  TAstr  = record s: array[0..2] of AnsiString; end;
var f1, f2: TFlat; n1, n2: TNest; s1, s2: TStr; d1, d2: TFlt;
    arr: array[0..2] of TFlat; pa, pb: PFlat; o1, o2: TOuter; calls: Integer;
    q1, q2: TArr; m1, m2: T2D; e1, e2: TArec; t1, t2: TAstr; i, j: Integer;

function Idx(i: Integer): Integer;
begin
  Inc(calls);
  Idx := i;
end;

function YN(v: Boolean): string;
begin
  if v then YN := 'T' else YN := 'F';
end;

procedure Row(const label_: string; got, want: Boolean);
begin
  WriteLn(label_, ' ', YN(got), ' want ', YN(want));
end;

begin
  f1.x := 1; f1.y := 2;
  f2.x := 1; f2.y := 2;   Row('flat same     ', f1 = f2, True);
                          Row('flat same-ne  ', f1 <> f2, False);
  f2.y := 999;            Row('flat tail     ', f1 = f2, False);
                          Row('flat tail-ne  ', f1 <> f2, True);
  f2.x := 9; f2.y := 2;   Row('flat first    ', f1 = f2, False);
  f2.x := 9; f2.y := 9;   Row('flat both     ', f1 = f2, False);

  n1.h := 1; n1.inner.p := 2; n1.inner.q := 3; n1.t := 4;
  n2.h := 1; n2.inner.p := 2; n2.inner.q := 3; n2.t := 4;
                          Row('nest same     ', n1 = n2, True);
  n2.inner.q := 99;       Row('nest inner    ', n1 = n2, False);
  n2.inner.q := 3; n2.t := 99;
                          Row('nest tail     ', n1 = n2, False);
  n2.t := 4; n2.h := 9;   Row('nest head     ', n1 = n2, False);

  { Two independently built heap strings with the same content: a HANDLE
    compare answers F for `same`, so this row separates content from identity
    as well as measuring the tail. }
  s1.k := 7; s1.s := 'the quick brown fox jumps over the lazy dog';
  s2.k := 7; s2.s := 'the quick brown fox jumps over the lazy do' + 'g';
                          Row('str  same     ', s1 = s2, True);
  s2.s := 'the quick brown fox jumps over the lazy doG';
                          Row('str  tail     ', s1 = s2, False);

  d1.a := 1.5; d1.b := 2.5; d2.a := 1.5; d2.b := 2.5;
                          Row('flt  same     ', d1 = d2, True);
  d2.b := 2.75;           Row('flt  tail     ', d1 = d2, False);

  { The four OPERAND SHAPES IRLowerAddress has to answer for, not just a plain
    variable: an element, a deref, a member, and an index expression with a
    SIDE EFFECT. The last one is the guard on the scratch-symbol parking -- the
    addresses are lowered once per operand, so `Idx` must be called twice and
    not once per member. A value node referenced by two parents is emitted by
    both, side effects included. }
  arr[0].x := 1; arr[0].y := 2;
  arr[1].x := 1; arr[1].y := 2;
  arr[2].x := 1; arr[2].y := 3;
                          Row('idx  same     ', arr[0] = arr[1], True);
                          Row('idx  tail     ', arr[0] = arr[2], False);
  pa := @arr[0]; pb := @arr[1];
                          Row('ptr  same     ', pa^ = pb^, True);
  pb := @arr[2];          Row('ptr  tail     ', pa^ = pb^, False);
  o1.tag := 5; o1.r.x := 1; o1.r.y := 2;
  o2.tag := 5; o2.r.x := 1; o2.r.y := 2;
                          Row('memb same     ', o1.r = o2.r, True);
  o2.r.y := 9;            Row('memb tail     ', o1.r = o2.r, False);
  calls := 0;
                          Row('side same     ', arr[Idx(0)] = arr[Idx(1)], True);
  WriteLn('side calls     ', calls, ' want 2');

  { ARRAY MEMBERS, unrolled one comparison per element. The discriminating row
    is always the LAST element: a one-word compare sees only the first machine
    word, which on a 32-bit target does not reach the array at all -- before
    2026-09-07 `arr1 first` answered T on arm32 and riscv32 as well.
    UFldArrLen is the FLAT element count, so the 2-D row's 12 cells need no
    dimension walk; `2d  last` is what catches a first-dimension-only count,
    which would compare 3 of 12 and answer a wrong T. }
  q1.n := 1; q2.n := 1;
  for i := 0 to 3 do begin q1.v[i] := 7; q2.v[i] := 7; end;
                          Row('arr1 same     ', q1 = q2, True);
  q2.v[3] := 9;           Row('arr1 last     ', q1 = q2, False);
  q2.v[3] := 7; q2.v[0] := 9;
                          Row('arr1 first    ', q1 = q2, False);
  for i := 0 to 2 do
    for j := 0 to 3 do begin m1.m[i, j] := i * 10 + j; m2.m[i, j] := i * 10 + j; end;
                          Row('2d   same     ', m1 = m2, True);
  m2.m[2, 3] := 99;       Row('2d   last     ', m1 = m2, False);
  m2.m[2, 3] := 23; m2.m[0, 1] := 99;
                          Row('2d   early    ', m1 = m2, False);
  for i := 0 to 2 do
  begin
    e1.e[i].p := i; e1.e[i].q := i + 1;
    e2.e[i].p := i; e2.e[i].q := i + 1;
  end;
                          Row('arec same     ', e1 = e2, True);
  e2.e[2].q := 99;        Row('arec last     ', e1 = e2, False);
  t1.s[0] := 'alpha'; t1.s[1] := 'beta';
  t1.s[2] := 'gamma, long enough to be a heap block';
  t2.s[0] := 'alpha'; t2.s[1] := 'beta';
  t2.s[2] := 'gamma, long enough to be a heap bloc' + 'k';
                          Row('astr same     ', t1 = t2, True);
  t2.s[2] := 'gamma, long enough to be a heap blocK';
                          Row('astr last     ', t1 = t2, False);
end.
