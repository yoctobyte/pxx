program test_p_a_conditional_directive_short_circuits_and;
{ `{$if declared(X) and (X <> Y)}` is FPC's portable idiom for "compare it only
  if it exists", and it is written that way BECAUSE `and` short-circuits. FPC's
  own compiler/rgobj.pas:1728 uses it on RS_STACK_POINTER_REG, which 1 of its 18
  cpubase files does not declare.

  pxx refused it outright: a shunting-yard applies the parenthesised `<>` BEFORE
  the `and`, so the comparison raised `has no integer value here` and no
  short-circuit could ever save it. The fix DEFERS that error instead of
  weakening it -- the comparison yields a slot with no value carrying the exact
  message, `and`/`or` may discard it on a decided LEFT operand, and one still
  standing at the end raises the message verbatim.

  WHY EVERY ROW BELOW USES A NAME NO PROFILE CAN DEFINE. An undefined symbol in
  a conditional pushes as "is it defined", so a row built on a name that some
  invocation DOES define silently stops testing the poison path and starts
  testing a define lookup -- it would still print `yes`, from the wrong
  machinery. `NOPE_*` names are chosen to be absent under every define profile.

  THE ASYMMETRY IS DELIBERATE AND IS ASSERTED, not left to chance: the rows
  marked `refused` below are refused by fpc 3.2.2 too. `<poison> and False` is
  False arithmetically, and answering it would accept a directive fpc rejects --
  in a conditional that is a DIFFERENT PROGRAM, not a different value. Left-only
  is exactly short-circuit semantics and nothing more. Those rows cannot live in
  this file (they halt the compile); they are asserted by the Makefile rows
  beside this one, which check the compile FAILS and names the operand. }
var fails: Integer;

procedure Check(const nm: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(nm, '=', 'yes')
  else begin WriteLn(nm, '=NO'); Inc(fails); end;
end;

const
{ `and` over an undeclared left operand: the arm must NOT be taken. }
{$if declared(NOPE_UNDECLARED_A) and (NOPE_UNDECLARED_A <> 3)}
  AND_TAKEN = True;
{$else}
  AND_TAKEN = False;
{$endif}
{ `or` over a decided-True left operand: the arm MUST be taken, and the
  comparison on the right must never be required to answer. }
{$if (not declared(NOPE_UNDECLARED_B)) or (NOPE_UNDECLARED_B <> 3)}
  OR_TAKEN = True;
{$else}
  OR_TAKEN = False;
{$endif}
{ A real comparison still compares -- both directions, so neither answer is the
  one a broken evaluator would give for free. }
  K = 4;
  N = 5;
{$if declared(K) and (K <> N)}
  DIFFERS_TAKEN = True;
{$else}
  DIFFERS_TAKEN = False;
{$endif}
{$if declared(K) and (K <> K)}
  SAME_TAKEN = True;
{$else}
  SAME_TAKEN = False;
{$endif}
{ Nested, so the poison has to survive being carried through an outer `and`
  rather than being discarded by the first operator it meets. }
{$if declared(K) and (declared(NOPE_UNDECLARED_C) and (NOPE_UNDECLARED_C > 0))}
  NESTED_TAKEN = True;
{$else}
  NESTED_TAKEN = False;
{$endif}

begin
  fails := 0;
  Check('and-undeclared-not-taken', AND_TAKEN, False);
  Check('or-short-circuits', OR_TAKEN, True);
  Check('real-comparison-differs', DIFFERS_TAKEN, True);
  Check('real-comparison-same', SAME_TAKEN, False);
  Check('nested-poison-discarded', NESTED_TAKEN, False);
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CONDSHORT OK') else WriteLn('CONDSHORT FAIL');
end.
