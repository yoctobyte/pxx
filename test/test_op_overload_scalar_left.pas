{ An operator whose LEFT operand is a built-in type — `1.5 + cx`, `3 * v` —
  which FPC accepts and this compiler refused at the declaration, with two
  different diagnostics depending on whether the type name happened to be one of
  the four builtin type TOKENS anyone had mapped back to a name.

  The negative rows are the point of the ticket, not decoration. The table is
  keyed on the LEFT operand, so an `(Integer, TVec)` operator registers under a
  plain Integer key: if the use sites consulted it by that key alone, `3 * 5`
  would compile into a call to a record operator. Every arithmetic row below
  that has no record in it is asserting that it did NOT.

  Every value measured against fpc 3.2.2 on this same source.
  feature-a-operator-table-keyed-on-both-operands }
program test_op_overload_scalar_left;
type
  TCx  = record re, im: Double; end;
  TVec = record x, y: Integer; end;
  TPt  = record a, b: Integer; end;

function MkCx(a, b: Double): TCx;
begin MkCx.re := a; MkCx.im := b; end;
function MkVec(a, b: Integer): TVec;
begin MkVec.x := a; MkVec.y := b; end;
function MkPt(a, b: Integer): TPt;
begin MkPt.a := a; MkPt.b := b; end;

{ a builtin type KEYWORD on the left — the row that failed to parse at all }
operator + (a: Double; b: TCx): TCx;
begin Result.re := a + b.re; Result.im := b.im; end;
{ ...and the same left type against a different record: the second key has to
  tell these two apart, because both register under (tkPlus, tyDouble). }
operator + (a: Double; b: TVec): TVec;
begin Result.x := Trunc(a) + b.x; Result.y := b.y; end;
{ an ordinary type NAME on the left — the row that parsed and was then refused }
operator * (a: Integer; b: TVec): TVec;
begin Result.x := a * b.x; Result.y := a * b.y; end;
{ the mirror image, which always worked; both must stay reachable }
operator * (a: TVec; b: Integer): TVec;
begin Result.x := a.x * b + 100; Result.y := a.y * b; end;
{ a comparison with a scalar left operand }
operator = (a: Integer; b: TVec): Boolean;
begin Result := (a = b.x); end;
{ two overloads sharing a left RECORD type and differing only in the right one.
  This is what the earlier "prefer the exact right-operand match" could never
  do: it read the right type off the operator's second PARAMETER SYMBOL, and
  those symbols are rolled back before the operator is registered, so a record
  right-operand never matched and the first-registered overload always won. }
operator - (a: TVec; b: TVec): TVec;
begin Result.x := a.x - b.x; Result.y := a.y - b.y; end;
operator - (a: TVec; b: TPt): TVec;
begin Result.x := a.x - b.a * 1000; Result.y := a.y - b.b * 1000; end;

var c: TCx; v: TVec; n: Integer; d: Double; ok: Boolean;

procedure Chk(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    ok := False;
  end;
end;

begin
  ok := True;

  c := 1.5 + MkCx(1, 2);
  Chk('double+cx re', Trunc(c.re * 10), 25);
  Chk('double+cx im', Trunc(c.im), 2);

  v := 2.9 + MkVec(1, 2);
  Chk('double+vec x', v.x, 3);
  Chk('double+vec y', v.y, 2);

  v := 3 * MkVec(1, 2);
  Chk('int*vec x', v.x, 3);
  Chk('int*vec y', v.y, 6);

  v := MkVec(1, 2) * 3;
  Chk('vec*int x', v.x, 103);
  Chk('vec*int y', v.y, 6);

  { the second key against two same-left-type overloads }
  v := MkVec(1, 2) - MkVec(10, 20);
  Chk('vec-vec x', v.x, -9);
  Chk('vec-vec y', v.y, -18);
  v := MkVec(1, 2) - MkPt(3, 4);
  Chk('vec-pt x', v.x, -2999);
  Chk('vec-pt y', v.y, -3998);

  { comparison, both answers }
  if not (1 = MkVec(1, 2)) then begin writeln('FAIL int=vec true'); ok := False; end;
  if (2 = MkVec(1, 2)) then begin writeln('FAIL int=vec false'); ok := False; end;

  { the negatives: arithmetic with no aggregate in it must stay arithmetic,
    with those very operators in scope }
  n := 3 * 5;
  Chk('int*int', n, 15);
  n := 7;
  if not (n = 7) then begin writeln('FAIL int=int'); ok := False; end;
  if (n = 8) then begin writeln('FAIL int<>int'); ok := False; end;
  d := 1.5 + 2.5;
  Chk('double+double', Trunc(d * 10), 40);

  if ok then writeln('ALL OK');
end.
