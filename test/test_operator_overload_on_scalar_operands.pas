{$mode objfpc}
program test_operator_overload_on_scalar_operands;
{ An operator overload on SCALAR operands -- no record, no class anywhere.

  pxx used to refuse the DECLARATION with "this operation is predefined for
  built-in operand types", a rule that really said "at least one operand must
  be a record or class". That is not fpc's rule. fpc's rule is that the
  operation must not ALREADY be defined for those operand types, and the
  difference is 92 of 209 measured same-type cells -- `operator - (a, b:
  AnsiString)`, `operator div (a, b: Single)`, `operator and (a, b: Char)`,
  `operator >< (a, b: LongInt)` are all legal fpc and were all refused.

  THE TWO HALVES ARE BOTH HERE ON PURPOSE, and neither is worth anything
  alone. Rows 1-3 prove a scalar overload FIRES: accepting the declaration
  without widening the use site leaves a silently inert operator, which is
  worse than the refusal it replaced. Rows 4-6 prove the builtins are
  untouched: `3 * 5` must not find the table. That partition is the whole
  safety argument -- a scalar entry can only exist for a pair the predefined
  table says False for, so "predefined -> builtin, otherwise -> table" splits
  the space instead of racing.

  ROW 6 IS `shr` AND IT IS NOT A DUPLICATE OF ROW 4. The lexer gives `shr` no
  token of its own: it arrives as a tkIdent whose text is 'shr' and both the
  declaration and the use site rename it to tkShrLogical on the way in. A
  predefined table naming Ord(tkShr) -- the ARITHMETIC shift, which is C's `>>`
  on a signed operand -- misses it, and `operator shr (a, b: LongInt)` was
  ACCEPTED while `shl` on the same pair was refused. One cell, found by the
  probe's shadow check and not by any row here, which is why the probe is the
  regression test for the table and this file is the regression test for the
  behaviour.

  ORACLE: fpc 3.2.2 prints this file's output exactly, measured.
  bug-p-the-operator-predefined-check-is-an-aggregate-approximation }

operator - (a, b: AnsiString) res : AnsiString;
begin
  res := a + '/' + b;
end;

operator >< (a, b: LongInt) res : LongInt;
begin
  res := a * 7 + b;
end;

operator ** (a, b: LongInt) res : LongInt;
begin
  res := a * 1000 + b;
end;

var
  x, y, s: AnsiString;
  i, j, n: LongInt;
begin
  x := 'x'; y := 'y';
  i := 5;   j := 6;

  { 1-3: the overloads FIRE -- none of these operations is predefined for
    these operand types, so the table is the only thing that can answer. }
  s := x - y;   WriteLn('minus-str: ', s);
  n := i >< j;  WriteLn('symdiff: ', n);
  n := i ** j;  WriteLn('pow: ', n);

  { 4-6: the builtins are UNTOUCHED -- these operations are predefined, so no
    lookup happens and no overload can shadow them. }
  WriteLn('mul: ', i * j);
  WriteLn('add: ', i + j);
  WriteLn('shr: ', i shr 1);
end.
