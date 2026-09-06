program test_a_half_dereferenced_chain_is_refused_var;
{ NEGATIVE HALF, variable spelling. `ppp^.a` on a three-deep pointer is ONE
  dereference short; it must not compile.

  It used to print 4310376 -- the pointer value truncated to four bytes -- where
  fpc 3.2.2 says `Illegal qualifier`. Us accepting what fpc rejects would not be
  a defect; a plausible wrong NUMBER is, and for a construct only a mistake
  produces the rule is to leave the mistake visible.

  THE DIAGNOSTIC ALREADY EXISTED AND ONE CARET MADE IT UNREACHABLE: write NO
  caret (`ppp.a`) and the same expression refuses cleanly, because there the
  guard's `recName = REC_NONE` conjunct holds. Write one where three are needed
  and ResolveDerefShape reports the ULTIMATE base record -- a true answer to a
  different question -- and the guard cannot fire.

  The POSITIVE half is test_a_pointer_cast_dereferences_implicitly_for_a_selector,
  every row of which is a chain that IS complete.
  bug-p-a-half-dereferenced-pointer-chain-answers-garbage-instead-of-refusing }
{$mode delphi}
type
  TRec = record a, b: Integer; end;
  PRec = ^TRec; PPRec = ^PRec; PPPRec = ^PPRec;
var
  r: TRec; p: PRec; pp: PPRec; ppp: PPPRec;
begin
  r.a := 11; r.b := 22; p := @r; pp := @p; ppp := @pp;
  WriteLn(ppp^.a);
end.
