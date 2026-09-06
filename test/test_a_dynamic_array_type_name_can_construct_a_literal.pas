program test_a_dynamic_array_type_name_can_construct_a_literal;

{ `TAB.Create(a, b, c)` -- Delphi's dynamic-array constructor. It is spelled
  like a class constructor and is not one: it is the element list `[a, b, c]`
  with the element type named on the left instead of inferred from the
  destination. fpc-testsuite tarrconstr1 / tarrconstr6.

  THE POINT OF THE THIRD AND FOURTH ROWS. The two literal spellings (`[...]` in
  a statement, `(...)` in a declaration) can only be retagged from an
  ASSIGNMENT, because that is where their element type is. This one carries its
  own type, so it must also work where there is no assignment at all -- as a
  CALL ARGUMENT, and nested inside another expression. A constructor that works
  only on the right of `:=` is half a feature, and the half that is missing is
  the half no row in the corpus spells. }

type
  TAB  = array of Byte;
  TLIA = array of LongInt;
  TSA  = array of AnsiString;
  TMat = array of array of LongInt;

function SumOf(const a: TLIA): LongInt;
var i, s: LongInt;
begin
  s := 0;
  for i := 0 to Length(a) - 1 do s := s + a[i];
  SumOf := s;
end;

var
  d: TAB;
  v: TLIA;
  s: TSA;
  m: TMat;
  i: LongInt;
begin
  i := 1;
  d := TAB.create(1 + 2, i);
  WriteLn('bytes len=', Length(d), ' d0=', d[0], ' d1=', d[1]);

  v := TLIA.Create(10, 20, 30);
  WriteLn('longs len=', Length(v), ' v0=', v[0], ' v2=', v[2]);

  { as a call ARGUMENT -- no assignment to read the element type off }
  WriteLn('arg sum=', SumOf(TLIA.Create(4, 5, 6)));

  { and inside a larger expression }
  WriteLn('nested sum=', SumOf(TLIA.Create(1, 2, 3)) + SumOf(v));

  s := TSA.Create('Alpha', 'Beta');
  WriteLn('strings len=', Length(s), ' s0=', s[0], ' s1=', s[1]);

  m := TMat.Create(TLIA.Create(1, 2), TLIA.Create(3, 4, 5));
  WriteLn('mat len=', Length(m), ' row0len=', Length(m[0]),
          ' row1len=', Length(m[1]), ' m11=', m[1][1]);

  { lowercase spelling, as tarrconstr1 writes it }
  v := TLIA.create(7);
  WriteLn('lower len=', Length(v), ' v0=', v[0]);
end.
