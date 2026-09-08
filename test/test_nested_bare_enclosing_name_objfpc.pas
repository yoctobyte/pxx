{ Reading the ENCLOSING function's bare, parameterless name from inside a nested
  routine. In objfpc that name is the enclosing function's RESULT VARIABLE, in
  every position except a call's `(`. pxx used to read it as a recursive CALL in
  both modes, because ParseNestedRoutine's enclosing-name rewrite fired only on
  `:=`, `.`, `[` and `^` and never consulted the mode -- while the sibling path
  for the SAME question in the function's own body (ParseFactorCore) had keyed on
  `not DelphiMode` all along. One concept, two paths, second path broken.

  THE COUNTER IS THE ASSERTION, NOT THE RETURNED VALUE. A result read and a
  recursive call return the SAME number at most depths, so a fixture checking
  only the value passes under both readings. `calls` separates them: fpc 3.2.2
  answers calls=1 here and pxx answered calls=2 before the fix.

  The delphi half of this question is test_nested_bare_enclosing_name_delphi.pas,
  where the correct answer is the opposite one. Both must exist: the ticket that
  reported this measured objfpc only and described a flat defect, when in delphi
  our behaviour was already right -- so the cell that was CORRECT was the cell
  with no assertion behind it, and a later widening would have deleted it as
  noise. Fix one dialect by breaking the other and one of these two goes red.
  bug-p-a-bare-enclosing-function-name-read-in-a-nested-routine-recurses }
{$mode objfpc}{$H+}
program test_nested_bare_enclosing_name_objfpc;
type
  TR = record F, G: LongInt; end;
var
  calls, depth, seen: LongInt;
  r: TR;

{ 1. bare read from a nested FUNCTION -- goes through the __outerres capture,
     because inside a nested function the token `Result` is already taken. }
function F: LongInt;
  function Inner: LongInt;
  begin
    if depth = 0 then begin Inc(depth); Inner := F; end else Inner := -1;
  end;
begin
  Inc(calls);
  Result := 40 + depth;
  WriteLn('inner=', Inner, ' res=', Result, ' calls=', calls);
end;

{ 2. bare read from a nested PROCEDURE -- rewritten to `Result` directly.
  3. a non-assign expression position: `if G > 0` and `G + 100`, which the
     `:=`-only test could never have reached.
  4. `@G` is the address of the RESULT VARIABLE, which is the row that killed
     an exception I had already written into the compiler on the reasoning that
     `@` obviously wants the routine. fpc settles it by writing through the
     pointer: `PLongInt(@G)^ := 99` inside the nested routine makes G return 99.
     Asserted that way here, because comparing the pointer against `@G` taken
     outside would pass for either reading in a build where they happened to
     differ for another reason.
  5. a FIELD named like the enclosing function: `r.G` is a selector on r and
     not this function at all. }
function G: LongInt;
  procedure Inner;
  begin
    if depth = 0 then
    begin
      Inc(depth);
      if G > 0 then seen := G + 100;
      PLongInt(@G)^ := 99;   { writes the enclosing RESULT }
      r.G := 7;
    end;
  end;
begin
  Inc(calls);
  Result := 40 + depth;
  Inner;
  WriteLn('res=', Result, ' calls=', calls, ' seen=', seen, ' rG=', r.G);
end;

{ 6. THE CONTROL, and it is the whole risk of the fix: an EXPLICIT `H()` from a
     nested routine must still recurse. A rewrite that fired on `(` too would
     turn this into a result read and print a wrong number rather than failing
     to build. }
function H: LongInt;
  function Inner: LongInt;
  begin
    if depth < 2 then begin Inc(depth); Inner := H(); end else Inner := 0;
  end;
begin
  Inc(calls);
  Result := Inner + 1;
end;

begin
  calls := 0; depth := 0; seen := 0; r.G := 0;
  WriteLn('F=', F, ' calls=', calls);
  calls := 0; depth := 0;
  WriteLn('G=', G, ' calls=', calls);
  calls := 0; depth := 0;
  WriteLn('H=', H, ' calls=', calls);
end.
