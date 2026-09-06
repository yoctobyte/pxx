program test_a_record_class_constructor_runs_before_the_program_body;
{ bug-p-a-class-constructor-is-accepted-and-never-runs -- THE SECOND SITE.

  The class body and the record body have SEPARATE member loops with separate
  termini, and `class constructor` fell through both. Fixing one arm of a double
  case and leaving the sibling is the shape this repo has a name for, so the
  record loop gets its own opener and its own row.

  terecs_u1.pp in the fpc testsuite is exactly this: delphi mode, `class
  constructor Create;` and `class destructor Destroy;` in a record, and fpc
  compiles it. That file is why the interim WARNED instead of refusing, and it
  is why the record arm exists rather than a refusal.

  TWO REFUSALS HAD TO BE KEPT APART FROM THIS ONE. pxx refuses a parameterless
  record CONSTRUCTOR (a record always exists, so a no-argument ctor is
  indistinguishable from its default state -- terecs17) and requires a record's
  class METHODS to be declared `static`. A `class constructor` is neither: it
  takes no receiver, allocates nothing, and Delphi does not spell `static` on
  it. Both rules now exempt it, and `Create`/`Destroy` here are the names
  terecs_u1.pp uses -- the collision is the point, not an accident.

  fpc 3.2.2 does not run the `class destructor` in either shape; pxx does, from
  FiniProcs[]. Nothing below asserts it, so this file stays comparable. }
{$mode delphi}
type
  TR = record
    class var M: Integer;
    class constructor Create;
    class destructor Destroy;
    class function Get: Integer; static;
  end;

var
  fails: Integer;
  Trace: AnsiString;

class constructor TR.Create; begin Trace := Trace + 'ctor;'; TR.M := 6; end;
class destructor TR.Destroy; begin TR.M := -1; end;
class function TR.Get: Integer; begin Result := TR.M; end;

procedure Check(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

procedure CheckS(const what, got, want: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got "', got, '" want "', want, '"');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  Trace := Trace + 'main;';
  CheckS('the record class constructor ran BEFORE the program body', Trace, 'ctor;main;');
  Check('and it set the class var', TR.Get, 6);
  Check('the class var is reachable through the type name', TR.M, 6);
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('RECCLASSCTORRUNS OK');
end.
