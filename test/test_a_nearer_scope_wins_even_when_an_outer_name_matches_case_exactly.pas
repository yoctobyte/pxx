program test_a_nearer_scope_wins_even_when_an_outer_name_matches_case_exactly;
{ bug-p-an-exact-case-match-in-an-outer-scope-beats-a-case-insensitive-one-in-a-nearer-scope

  Pascal is case-insensitive and the NEAREST scope wins. `FindSym` used to make
  TWO FULL WALKS of the symbol chain -- exact-case, then case-insensitive -- so
  case-exactness was ranked ABOVE scope depth and an exact match in ANY visible
  scope beat a case-insensitive match in a nearer one:

      var counter: LongInt;
      procedure Bump(Counter: Integer);
      begin counter := 55; end;      -- wrote the GLOBAL, left the parameter at 7

  Both halves wrong, in opposite directions, with no diagnostic -- and
  `--strict-case` did not fire on it either. The comment above those two walks
  said "innermost scope out (preserves shadowing)", which is true WITHIN a walk
  and false across two of them; comment and code disagreed and the comment was
  the correct one.

  ROW 6 IS THE CONTROL THAT NAMES THE MECHANISM, and without it this file would
  merely be evidence that case-folding was broken somewhere. With NO exact-case
  match anywhere -- global `COUNTER`, local `Counter`, reference `counter` --
  BOTH compilers already picked the local before the fix, because the exact walk
  found nothing and the ordinary innermost-first order then applied. So the
  defect was never "pxx folds case wrong"; it was the ORDER of two walks.

  Rows 1, 4 and 7 passed before the fix as well and are the boundary: a
  same-case reference, a differently-cased LOCAL variable in a routine with no
  outer collision, and a mixed-case for-loop variable. A file with only the
  failing rows cannot tell a fix from a change.

  Every row is byte-identical to fpc 3.2.2. }

var
  counter: LongInt;
  COUNTER2: LongInt;
  fails: Integer;
  seen: LongInt;

procedure Check(const what: AnsiString; g, w: LongInt);
begin
  if g <> w then
  begin
    WriteLn('FAIL ', what, ': got ', g, ' want ', w);
    fails := fails + 1;
  end;
end;

{ 1: a SAME-case reference. Passed before the fix; here as the boundary. }
procedure SameCase(counter: Integer);
begin
  counter := 55;
  seen := counter;
end;

{ 2: the row this file exists for -- a differently-cased WRITE. }
procedure DiffCaseWrite(Counter: Integer);
begin
  counter := 55;      { the parameter, spelled in lower case }
  seen := Counter;
end;

{ 3: the same defect on the READ side, and on a by-ref intrinsic. }
procedure DiffCaseRead(Counter: Integer);
begin
  seen := counter;    { must read the PARAMETER, not the global }
end;

procedure DiffCaseInc(Counter: Integer);
begin
  Inc(counter);       { must bump the PARAMETER }
  seen := Counter;
end;

{ 4: a differently-cased LOCAL, shadowing a global of the same name. }
procedure DiffCaseLocal;
var Counter: LongInt;
begin
  Counter := 42;
  seen := counter;
end;

{ 5: a NESTED routine reaching its enclosing routine's local, differently
  cased, with a global of that name also in scope. The two-walk order lost
  this one too, and it is the shape that says the rule is about DEPTH. }
procedure Outer;
var Counter: LongInt;

  procedure Inner;
  begin
    seen := counter;   { Outer's local, not the program's }
  end;

begin
  Counter := 77;
  Inner;
end;

{ 6: THE CONTROL. No exact-case match anywhere: the global is COUNTER2, the
  local is Counter2, the reference is counter2. This row was already right
  before the fix, which is what identifies the two-walk ORDER as the cause. }
procedure NoExactAnywhere;
var Counter2: LongInt;
begin
  Counter2 := 42;
  seen := counter2;
end;

{ 7: a mixed-case for-loop variable with no outer collision. Boundary. }
procedure ForVarMixedCase;
var i: LongInt;
begin
  seen := 0;
  for I := 1 to 3 do seen := seen + i;
end;

begin
  fails := 0;

  counter := -1; seen := 0; SameCase(7);
  Check('1: same-case parameter, global untouched', counter, -1);
  Check('1: same-case parameter, parameter written', seen, 55);

  counter := -1; seen := 0; DiffCaseWrite(7);
  Check('2: diff-case write, global untouched', counter, -1);
  Check('2: diff-case write, parameter written', seen, 55);

  counter := -1; seen := 0; DiffCaseRead(7);
  Check('3: diff-case read reaches the parameter', seen, 7);

  counter := -1; seen := 0; DiffCaseInc(7);
  Check('3: Inc on a diff-case parameter, global untouched', counter, -1);
  Check('3: Inc on a diff-case parameter, parameter bumped', seen, 8);

  counter := -1; seen := 0; DiffCaseLocal;
  Check('4: diff-case local read', seen, 42);
  Check('4: diff-case local, global untouched', counter, -1);

  counter := -1; seen := 0; Outer;
  Check('5: nested routine reaches the enclosing local', seen, 77);

  COUNTER2 := -1; seen := 0; NoExactAnywhere;
  Check('6: CONTROL, no exact match anywhere', seen, 42);
  Check('6: CONTROL, global untouched', COUNTER2, -1);

  seen := 0; ForVarMixedCase;
  Check('7: mixed-case for-loop variable', seen, 6);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CASESHADOW OK');
end.
