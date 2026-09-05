{ A `^` AFTER A MEMBER THAT THE CAST WALK HANDED TO THE SHARED SELECTOR PARSER.

  `PTC(raw)^.GetP^` and `PTC(raw)^.Pp^` were refused outright — "expected ')'
  before '^'" — while `pc^.GetP^` and `pc^.Pp^`, the identical chains off a
  plain variable, compiled and printed the right value. fpc 3.2.2 accepts all
  four. Pre-dates pin v403.

  Cause: the pointer-alias cast's hand-rolled postfix walk delegates a METHOD
  or PROPERTY name to ParseClassRecordSelectors, whose own loop is
  [tkDot, tkLBrack] with NO tkCaret in it — so a following `^` was left in the
  token stream and nobody consumed it. The record-name cast twin had learned
  the same lesson separately, months earlier, on `TA(b).pi^`.

  EVERY CAST ROW IS PAIRED WITH THE SAME CHAIN OFF A VARIABLE, and the pair is
  the point: the variable spelling was right throughout, on the pinned compiler
  too, which is what says the defect is the OPENER and not the shape. A cast row
  alone could not tell a fixed walk from a language that never allowed this.

  Rows 5/6 and 7/8 are the tag half rather than the parse half. Consuming the
  token is not enough — the deref must also be TYPED from the value in hand and
  not from the alias the expression was cast through. A Char prints as an
  ordinal when the tag is wrong and the bytes are right, which is how every
  other instance of this was found; `^PInteger` through a property exercises
  the depth carried on the deref node.

  refactor-p-three-hand-rolled-postfix-loops (fixed there, not filed separately) }
program test_a_deref_after_a_delegated_member_on_a_pointer_cast;
type
  TR = record a: Integer; end;
  PR = ^TR;
  PPI = ^PInteger;
  TC = class
    fr: PR;
    fc: PChar;
    fpp: PPI;
    function GetR: PR;
    property Pr: PR read fr;
    property Pc: PChar read fc;
    property Ppp: PPI read fpp;
  end;
  PTC = ^TC;
var
  c: TC; pc: PTC; raw: Pointer; r: TR; ch: array[0..3] of Char;
  n: Integer; pi: PInteger;
function TC.GetR: PR; begin Result := fr; end;
begin
  r.a := 7; ch[0] := 'Z'; ch[1] := #0; n := 99; pi := @n;
  c := TC.Create; c.fr := @r; c.fc := @ch[0]; c.fpp := @pi;
  pc := @c; raw := pc;
  WriteLn('1 var  meth rec  ', pc^.GetR^.a);
  WriteLn('2 cast meth rec  ', PTC(raw)^.GetR^.a);
  WriteLn('3 var  prop rec  ', pc^.Pr^.a);
  WriteLn('4 cast prop rec  ', PTC(raw)^.Pr^.a);
  WriteLn('5 var  prop char ', pc^.Pc^);
  WriteLn('6 cast prop char ', PTC(raw)^.Pc^);
  WriteLn('7 var  prop pp   ', pc^.Ppp^^);
  WriteLn('8 cast prop pp   ', PTC(raw)^.Ppp^^);
end.
