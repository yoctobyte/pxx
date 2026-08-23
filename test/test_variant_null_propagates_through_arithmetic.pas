program test_variant_null_propagates_through_arithmetic;
{ An ARITHMETIC operator with a Null operand yields Null -- FPC's rule, inherited
  from OLE and shared with SQL. pxx read VT_EMPTY's payload as 0 and carried on,
  so `Null + 5` was 5 and `Null * 5` was 0: a missing value silently became a
  real one, which is the single failure mode Null exists to prevent. A Null
  column summed into a total contributed 0 and the total looked plausible.

  COMPARISON is deliberately NOT part of the rule and is asserted here to keep it
  that way: FPC answers False for `Null = 5` and True for `Null <> 5`.

  VT_EMPTY spells both Null and Unassigned in this implementation, and one tag is
  enough for the propagation ANSWER -- measured against fpc 3.2.2, `Unassigned +
  5` is not 5 either, it is Unassigned; FPC propagates both, each as itself. The
  residual difference is only which of VarIsNull/VarIsEmpty answers True
  afterwards, an approximation lib/rtl/variants.pas' header already documents,
  so this test asserts through VarIsNull only.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 agrees with every VarIsNull row below. }
{$mode objfpc}{$H+}
uses variants;
var
  a, b, c: Variant;
  fails: Integer;

procedure ChkB(const what: string; got, want: Boolean);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { --- Null on the LEFT --- }
  a := Null; b := 5;    c := a + b;    ChkB('null+int',  VarIsNull(c), True);
  a := Null; b := 5;    c := a - b;    ChkB('null-int',  VarIsNull(c), True);
  a := Null; b := 5;    c := a * b;    ChkB('null*int',  VarIsNull(c), True);
  a := Null; b := 5;    c := a / b;    ChkB('null/int',  VarIsNull(c), True);
  a := Null; b := 5;    c := a div b;  ChkB('null div',  VarIsNull(c), True);
  a := Null; b := 5;    c := a mod b;  ChkB('null mod',  VarIsNull(c), True);
  a := Null; b := 2.5;  c := a + b;    ChkB('null+dbl',  VarIsNull(c), True);
  a := Null; b := 'x';  c := a + b;    ChkB('null+str',  VarIsNull(c), True);

  { --- Null on the RIGHT --- }
  a := 5;    b := Null; c := a + b;    ChkB('int+null',  VarIsNull(c), True);
  a := 5;    b := Null; c := a - b;    ChkB('int-null',  VarIsNull(c), True);
  a := 5;    b := Null; c := a * b;    ChkB('int*null',  VarIsNull(c), True);
  a := 'x';  b := Null; c := a + b;    ChkB('str+null',  VarIsNull(c), True);

  { --- both --- }
  a := Null; b := Null; c := a + b;    ChkB('null+null', VarIsNull(c), True);

  { --- COMPARISON is NOT propagation: a Null compares unequal, it does not
        answer Null. This is the row that must not change if the propagation
        rule is ever widened. --- }
  a := Null; b := 5;    ChkB('null=int',   a = b,  False);
  a := Null; b := 5;    ChkB('null<>int',  a <> b, True);
  a := 5;    b := Null; ChkB('int=null',   a = b,  False);

  { --- an ordinary arithmetic row, to prove the guard did not eat the value
        path (payload 0 is NOT Null: `0 + 5` is 5, not Null) --- }
  a := 0;    b := 5;    c := a + b;    ChkB('zero+int not null', VarIsNull(c), False);
  ChkB('zero+int value', Integer(c) = 5, True);
  a := 3;    b := 4;    c := a * b;    ChkB('int*int value', Integer(c) = 12, True);

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
