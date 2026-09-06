program test_an_open_array_slice_passes_a_sub_range;

{ `a[lo..hi]` passed to an open-array parameter. fpc-testsuite tarray7.

  A SLICE IS NOT A VALUE, IT IS A VALUE PLUS A WRITE-BACK OBLIGATION, which is
  what the `var` rows below assert and what no existing node could carry --
  `Copy(a, lo, n)` is a perfectly good value and discards exactly the obligation.

  EVERY SLICE ROW IS PAIRED WITH ITS WHOLE-ARRAY SIBLING, and the reason is a
  measurement, not tidiness: while this was being built, a slice spanning the
  WHOLE base was correct while a proper sub-range was not, and the corpus row
  that motivated the work spells only the whole-base case. A row whose bounds
  cannot be wrong cannot report that the bounds are wrong. So no row here slices
  from the first element to the last. }

function Sum(const r: array of LongInt): LongInt;
var i, s: LongInt;
begin
  s := 0;
  for i := 0 to High(r) do s := s + r[i];
  Sum := s;
end;

function Count(const r: array of LongInt): LongInt;
begin
  Count := Length(r);
end;

procedure Upper(var u: array of Char);
var i: LongInt;
begin
  for i := Low(u) to High(u) do u[i] := UpCase(u[i]);
end;

var
  a: array[1..6] of LongInt;      { static, low bound 1 }
  n: array[-2..2] of LongInt;     { static, NEGATIVE low bound }
  c: array of LongInt;            { dynamic }
  p: ^LongInt;                    { typed pointer over a heap block }
  d: array[1..10] of Char;
  i: LongInt;
begin
  for i := 1 to 6 do a[i] := i;
  WriteLn('static whole=', Sum(a), ' len=', Count(a));
  WriteLn('static 2..4=', Sum(a[2..4]), ' len=', Count(a[2..4]));
  WriteLn('static 1..2=', Sum(a[1..2]), ' len=', Count(a[1..2]));
  WriteLn('static 6..6=', Sum(a[6..6]), ' len=', Count(a[6..6]));

  { A NEGATIVE low bound is the row that catches an arm normalising to zero.
    The values are `(i + 5) * 10` and NOT `i * 10`: the symmetric version sums to
    0 for the whole array AND for the -1..1 slice, so both rows would print the
    same 0 that a slice returning nothing prints. An expected value that collides
    with the failure value is a row that cannot fail. }
  for i := -2 to 2 do n[i] := (i + 5) * 10;
  WriteLn('neg whole=', Sum(n), ' len=', Count(n));
  WriteLn('neg -1..1=', Sum(n[-1..1]), ' len=', Count(n[-1..1]));

  SetLength(c, 6);
  for i := 0 to 5 do c[i] := (i + 1) * 100;
  WriteLn('dyn whole=', Sum(c), ' len=', Count(c));
  WriteLn('dyn 1..3=', Sum(c[1..3]), ' len=', Count(c[1..3]));

  GetMem(p, 6 * SizeOf(LongInt));
  for i := 0 to 5 do p[i] := i + 1;
  WriteLn('ptr 0..2=', Sum(p[0..2]), ' len=', Count(p[0..2]));
  WriteLn('ptr 3..5=', Sum(p[3..5]), ' len=', Count(p[3..5]));
  FreeMem(p);

  { the WRITE-BACK obligation: a var open-array slice must reach the caller's
    own elements, and must not touch the elements outside the slice }
  d := 'abcdefghij';
  Upper(d[3..6]);
  WriteLn('var slice=', d);
  Upper(d[1..2]);
  WriteLn('var again=', d);
  Upper(d);
  WriteLn('var whole=', d);
end.
