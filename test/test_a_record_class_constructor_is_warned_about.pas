program test_a_record_class_constructor_is_warned_about;
{ bug-p-a-class-constructor-is-accepted-and-never-runs -- THE SECOND SITE.

  The class body and the record body have SEPARATE member loops with separate
  termini, and `class constructor` falls through both. Guarding only the class
  one is the half-fix this repo has a name for: fix one arm of a double case
  and the sibling stays broken and looks covered.

  THIS FILE IS NOT EXPECTED TO COMPILE, AND THE RECIPE DOES NOT ASSERT THAT IT
  DOES NOT. What is asserted is only that the WARNING is on the log. pxx refuses
  a parameterless record constructor and a bare record destructor for reasons
  that have nothing to do with this ticket, and both refusals arrive after the
  warning; asserting the refusal here would write those unrelated rules into
  this ticket's guard and make fixing either of them look like a regression.
  Grepping the log for the warning is the claim that survives whichever way
  those go.

  terecs_u1.pp in the fpc testsuite is this exact shape -- {$mode delphi},
  `class constructor Create;` and `class destructor Destroy;` in a record, with
  `{ %norun }` -- and fpc compiles it. That is why the diagnostic here is a
  warning and not an Error. }
type
  TR = record
    class var M: Integer;
    class constructor Create;
    class destructor Destroy;
  end;

class constructor TR.Create; begin TR.M := 6; end;
class destructor TR.Destroy; begin end;

begin
  WriteLn('M=', TR.M);
end.
