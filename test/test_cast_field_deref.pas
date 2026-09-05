{ A `^` AFTER a field reached through a CAST must use the field's pointee, not
  the record the expression was cast to. Three postfix walkers had a private
  notion of what a `^` yields, and all three got it from the cast:

    TA(b).pi^        rvalue, pasparser_expr.inc: the record-name cast arm
                     Break'd out of its own loop after delegating the `.name`
                     to ParseClassRecordSelectors -- whose loop is
                     [tkDot, tkLBrack] with no tkCaret -- so the `^` was never
                     consumed at all. "expected ')' before '^'" in argument
                     position, "a statement cannot start with '^'" in an
                     assignment.

    TA(b).pi^ := 7   target, pasparser_stmt.inc: the caret arm stamped
                     tyRecord and the CAST's record on the deref, so the store
                     was refused, "cannot assign Integer to record".

    PA(q)^.pi^ := 7  target, pasparser_stmt.inc: this loop already CALLED
                     ResolveDerefShape and was right; its answer was then
                     discarded by an adapter fallback whose test --
                     tyInteger + REC_NONE + no depth -- is both the resolver's
                     decline signature AND a true answer for `^Integer`.

  The `var` rows are the control that says these are about the OPENER: the same
  chains off a plain variable and off a pointer variable were correct
  throughout, on the pinned compiler too. The `PChar` rows are the control for
  the adapter fallback the third fix narrowed -- it must still fire where it is
  the right answer.

  Found by the escape census in refactor-p-three-hand-rolled-postfix-loops:
  these were the loops reaching ParseClassRecordSelectors WITHOUT
  ResolveDerefShape. No bug report was involved.
  Expected output is fpc 3.2.2 -Mdelphi -O1. }
program test_cast_field_deref;
type
  PInt = ^Integer;
  PPInt = ^PInt;
  TA = record pi: PInt; pc: PChar; ppi: PPInt; end;
  TB = record pi: PInt; pc: PChar; ppi: PPInt; end;
  PA = ^TA;
var
  b: TB;
  iv: Integer;
  q: Pointer;
  vpa: PA;
  s: array[0..9] of Char;
  pv: PInt;
begin
  iv := 42; s[0] := 'Z'; s[1] := #0; pv := @iv;
  b.pi := @iv; b.pc := @s[0]; b.ppi := @pv;
  q := @b; vpa := @b;

  { reads }
  WriteLn('var=', b.pi^);
  WriteLn('vardrf=', vpa^.pi^);
  WriteLn('reccast=', TA(b).pi^);
  WriteLn('reccastc=', TA(b).pc^);
  WriteLn('reccast2=', TA(b).ppi^^);
  WriteLn('alias=', PA(q)^.pi^);
  WriteLn('aliasc=', PA(q)^.pc^);

  { stores }
  TA(b).pi^ := 7;    WriteLn('sreccast=', iv);
  PA(q)^.pi^ := 11;  WriteLn('salias=', iv);
  vpa^.pi^ := 13;    WriteLn('svardrf=', iv);
  b.pi^ := 17;       WriteLn('svar=', iv);
  PA(q)^.ppi^^ := 19; WriteLn('salias2=', iv);
  TA(b).pc^ := 'Y';  WriteLn('sreccastc=', s[0]);

  { the PChar adapter cast, which the narrowed fallback must still serve }
  WriteLn('adapter=', PChar(@s[0])^);
  PChar(@s[0])^ := 'Q';
  WriteLn('sadapter=', s[0]);

  WriteLn('CAST FIELD DEREF OK');
end.
