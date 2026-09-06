program test_a_class_constructor_runs_once_before_the_program_body;
{ bug-p-a-class-constructor-is-accepted-and-never-runs

  `class constructor` and `class destructor` were not in the class body's
  hand-maintained `class X` lookahead list, so they fell past every arm to the
  member-loop terminus, which stepped over the `class` keyword and let the
  ORDINARY constructor arm take what was left. The class-ness was discarded and
  the routine was wired to nothing: the body compiled into code nothing could
  reach, `TC.Init;` was refused with `expected ':=' before ';'`, and class-level
  state stayed at its zero value with no diagnostic.

  Two halves, and the first alone is not the fix. The class body now has an
  opener that registers it as a STATIC class method (not a constructor -- a
  constructor would allocate), so the name resolves. What makes it RUN is
  ParseSubroutine registering the IMPLEMENTATION body in InitProcs[], the same
  list a unit's `initialization` section joins, called before the program body.

  ORDER IS THE CLAIM, NOT JUST THE VALUE. `N=5 by the time main runs` would also
  be true of a class constructor called by hand from the first line of main, so
  the file records the SEQUENCE: Trace accumulates, and the program body's first
  act is to append 'main'. fpc 3.2.2 prints the class constructor's own output
  before the program body's first line, which is what says "before", and this
  file asserts the same order without depending on stdout interleaving.

  THE NAME `Init` IS LOAD-BEARING and was measured. With the class-ness
  discarded, `class constructor TC.Create` demoted to an ordinary constructor
  called Create, so `TC.Create` ran its body as an instance constructor and N
  came back 5 -- a different wrong answer wearing the shape of a right one. A
  name that cannot collide with the implicit constructor is what separates
  "the class constructor ran" from "something called Create".

  NO ROW CALLS `TC.Init` BY HAND, deliberately. It resolves now -- the ticket's
  own evidence of brokenness was that `TC.Init;` answered `expected ':=' before
  ';'` -- but fpc refuses the explicit call (`identifier idents no member
  "Init"`) and so does Delphi, so asserting it here would make this file
  uncomparable with fpc for the sake of an extension nobody asked for. The rows
  that remain are byte-identical under both compilers.

  WHAT FPC DOES NOT DO: fpc 3.2.2 does not run the `class destructor` at all,
  measured in both shapes (the class in the program, and the class in a unit).
  pxx runs it at exit, from FiniProcs[], which is what the source says should
  happen and what Delphi documents. Us doing what the source says is not a
  divergence to chase back. }
type
  TC = class
    class var N: Integer;
    class constructor Init;
    class destructor Done;
    class procedure Bump;
    class function Get: Integer;
  end;

var
  fails: Integer;
  Trace: AnsiString;

class constructor TC.Init; begin Trace := Trace + 'ctor;'; TC.N := 5; end;
class destructor TC.Done; begin TC.N := -1; end;
class procedure TC.Bump; begin TC.N := TC.N + 1; end;
class function TC.Get: Integer; begin Get := TC.N; end;

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

var
  o: TC;
begin
  fails := 0;
  Trace := Trace + 'main;';

  { THE ROW THIS FILE EXISTS FOR: the class constructor has already run. }
  CheckS('the class constructor ran BEFORE the program body', Trace, 'ctor;main;');
  Check('and it set the class var', TC.Get, 5);

  { ...and exactly once. A second look at the same state is not a second run;
    what would show a double registration is the trace, which holds one 'ctor;'. }
  CheckS('exactly once', Trace, 'ctor;main;');

  { The class members that already worked still work — the opener must not have
    swallowed the ordinary `class procedure`/`class function` spellings. }
  TC.N := 0;
  TC.Bump;
  Check('class procedure still runs', TC.Get, 1);

  { The implicit constructor is untouched: registering the class constructor as
    a class method rather than as a constructor is what keeps these apart. }
  TC.N := 1;
  o := TC.Create;
  Check('an instance is still constructible', TC.Get, 1);
  o.Free;

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CLASSCTORRUNS OK');
end.
