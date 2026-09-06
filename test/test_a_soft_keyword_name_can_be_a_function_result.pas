program test_a_soft_keyword_name_can_be_a_function_result;
{$mode objfpc}
{ `exit`, `halt`, `break` and `continue` are SOFT keywords -- they lex as plain
  identifiers and ParseStatementAST dispatches on the NAME -- so a user routine
  may be called any of them, and always could be. What could NOT be done is the
  other half of writing one: ASSIGNING ITS RESULT BY ITS OWN NAME.

    function exit(x: LongInt): Boolean;
    begin
      exit := x > 0;        { pascal26: a statement cannot start with ':=' }
    end;

  The Halt/Exit arm took the name, consumed it, produced AN_EXIT, and left the
  `:=` for the caller to trip over. `Result := x > 0` in the same function
  compiled and ran, which is what made this read as a DECLARATION problem in
  the ticket that reported it: the routine declares fine and always did.

  Every row below is fpc 3.2.2's own answer -- exit codes included, since the
  point of three of these names is what they do to control flow. }

var
  i: Integer;

{ ---- the four soft-keyword names, each assigning its result by its own name ---- }

function exit(x: LongInt): LongInt;
begin
  exit := x + 1;
end;

function halt(x: LongInt): LongInt;
begin
  halt := x + 2;
end;

function break(x: LongInt): LongInt;
begin
  break := x + 3;
end;

function continue(x: LongInt): LongInt;
begin
  continue := x + 4;
end;

{ ---- and in {$mode delphi}, which is the row that says WHICH predicate ---- }
{ A bare own-name READ is a reference to the routine in Delphi and never the
  result var -- that is OwnNameResultSym's rule and it is right. A WRITE is the
  Result synonym in Delphi too: fpc 3.2.2 -Mdelphi compiles and runs this. Ask
  the read predicate here and the row below is refused for a rule that is about
  the other direction. }
{$mode delphi}
function exitd(x: LongInt): LongInt;
begin
  exitd := x + 5;
end;
{$mode objfpc}

{ ---- and the control that stays IN this file ---- }
{ The bare STATEMENT forms cannot be exercised here, and pxx and fpc 3.2.2 agree
  on why, to the line: once `break` and `continue` are declared as one-parameter
  functions, `if i = 3 then continue;` is `Wrong number of parameters specified
  for call to "continue"` in BOTH. Shadowing is total for these in both
  compilers, so the unshadowed statements are asserted by
  test_a_soft_keyword_statement_still_works.pas, which declares none of them.

  What this file CAN assert about the intrinsic, and does at the end, is that
  `halt(5)` reaches the FUNCTION: if it reached the intrinsic the program would
  exit 5 and the last line would never print. That row is the difference between
  a test of four declarations and a test of four declarations that are actually
  bound to. }

begin
  writeln('exit    ', exit(10));
  writeln('halt    ', halt(10));
  writeln('break   ', break(10));
  writeln('continue ', continue(10));
  writeln('delphi  ', exitd(10));
  halt(5);                       { the FUNCTION -- its result is discarded, so
                                   this must NOT end the program: the next line
                                   is the assertion that it did not }
  writeln('after-halt-call');
end.
