{ Relational operators in a CONSTANT expression, and the Boolean type that
  comes out of them.

  Before feature-p-relational-operators-in-a-const-expression, ConstEval had no
  relational level at all -- it stopped at `+ - or xor`. So

      const F = 1 > 0;                  -> "Expected: begin", at the `>`
      const G = (1 > 0) and (2 < 3);    -> same, at the `>` inside the parens

  while `const B = True and False;` worked, so booleans were half supported.
  The idiom this blocked is the portability constant,
  `const Is64 = SizeOf(Pointer) = 8`.

  The second half is the TYPE. ConstEval collapses every ordinal to an Int64,
  so a folded boolean declared as tyInteger prints 1 rather than TRUE, boxes as
  vtInteger in `array of const`, and does not match a Boolean parameter. CEIsBool
  carries the fact out of band: a relational sets it, `and`/`or`/`xor` keep it
  only when BOTH operands are boolean, `not` keeps it, everything else clears it.

  Output is byte-identical to fpc 3.2.2 -Mobjfpc -O1's on this source. }
program test_const_boolean_expression;

const
  A  = 5;
  B  = 10;
  Sz = 4;

  { relational forms }
  R_gt   = 1 > 0;
  R_lt   = 1 < 0;
  R_eq   = A = 5;
  R_ne   = A <> 5;
  R_ge   = A >= 5;
  R_le   = A <= 4;
  R_chr  = 'a' < 'b';          { a single-char literal as an OPERAND, not the const }
  R_expr = A + 1 = 6;          { relational binds loosest: (A + 1) = 6 }
  R_size = SizeOf(Pointer) = 8;

  { boolean-ness propagating through the other operators }
  P_and  = (1 > 0) and (2 < 3);
  P_or   = R_lt or R_gt;
  P_not  = not R_gt;           { LOGICAL not: bitwise `not 1` is -2, a non-zero
                                 Boolean, which printed TRUE }
  P_notT = not True;
  P_named = R_gt and R_eq;     { a Boolean-typed NAMED const stays Boolean }

  { and NOT propagating: these must stay integers }
  I_and  = 6 and 3;
  I_or   = 4 or 1;
  I_not  = not 0;
  I_mix  = 2 + 3 * 4;

var
  arr: array[0..Sz-1] of Integer;
  fails: Integer;

procedure ChkB(const nm: string; got, want: Boolean);
begin
  if got = want then WriteLn(nm, ' ok')
  else begin WriteLn(nm, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

procedure ChkI(const nm: string; got, want: Int64);
begin
  if got = want then WriteLn(nm, ' ok')
  else begin WriteLn(nm, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

{ a Boolean PARAMETER only accepts the const if it was typed Boolean }
procedure TakesBool(b: Boolean);
begin
  WriteLn('param ', b);
end;

begin
  fails := 0;

  ChkB('gt', R_gt, True);      ChkB('lt', R_lt, False);
  ChkB('eq', R_eq, True);      ChkB('ne', R_ne, False);
  ChkB('ge', R_ge, True);      ChkB('le', R_le, False);
  ChkB('chr', R_chr, True);    ChkB('expr', R_expr, True);
  ChkB('size', R_size, True);

  ChkB('and', P_and, True);    ChkB('or', P_or, True);
  ChkB('not', P_not, False);   ChkB('notTrue', P_notT, False);
  ChkB('named', P_named, True);

  ChkI('int.and', I_and, 2);   ChkI('int.or', I_or, 5);
  ChkI('int.not', I_not, -1);  ChkI('int.mix', I_mix, 14);

  { the TYPE, not just the value: printed as a Boolean, and accepted by a
    Boolean parameter }
  WriteLn('print ', R_gt, ' ', P_not);
  TakesBool(R_gt);

  { an ordinary const expression must still size an array }
  ChkI('arraybound', Length(arr), 4);
  ChkI('sum', A + B, 15);

  if fails = 0 then WriteLn('ALL OK') else WriteLn('FAILURES ', fails);
end.
