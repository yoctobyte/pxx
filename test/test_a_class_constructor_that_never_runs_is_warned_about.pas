program test_a_class_constructor_that_never_runs_is_warned_about;
{ bug-p-a-class-constructor-is-accepted-and-never-runs

  `class constructor` and `class destructor` are not in the class body's
  hand-maintained `class X` lookahead list, so they fall past every arm to the
  member-loop terminus, which steps over the `class` keyword and lets the
  ORDINARY constructor arm take what is left. The class-ness is discarded and
  FPC's semantics -- run once, automatically, before the class is first used --
  are attached to nothing: the body compiles into code nothing can reach, and
  an explicit `TC.Init;` is refused with `expected ':=' before ';'`.

  THIS FILE ASSERTS THE WARNING, NOT THE VALUE, ON PURPOSE. Asserting N=0 here
  would write today's wrong answer into the suite and fail the day somebody
  implements the construct properly -- the fix would look like the regression.
  What must not silently change is that the compiler SAYS SO; the value belongs
  to the ticket. The warning itself is checked by the Makefile against this
  file's own compile log, because a program cannot read its own diagnostics.

  The runtime rows below are the OTHER half: they prove the file still compiles
  and runs, i.e. that the warning is a warning and not a refusal. Warning where
  terecs_u1.pp -- a {$mode delphi} record with `class constructor Create` that
  fpc compiles -- would have to be refused is the whole reason this is not an
  Error. }
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

class constructor TC.Init; begin TC.N := 5; end;
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

var
  o: TC;
begin
  fails := 0;
  { The class members that DO work still work -- the point of warning rather
    than refusing is that the surrounding declaration keeps its meaning. }
  TC.N := 0;
  TC.Bump;
  Check('class procedure still runs', TC.Get, 1);
  { NAMED `Init`, NOT `Create`, AND THE NAME IS LOAD-BEARING: with the class-ness
    discarded, `class constructor TC.Create` demotes to an ORDINARY constructor
    called Create, so `TC.Create` runs its body as an instance constructor and
    N comes back 5. That is a different wrong answer wearing the shape of a
    right one -- measured here, 2026-09-06 -- and it is why the ticket's repro
    uses a name that cannot collide. }
  o := TC.Create;
  Check('an instance is still constructible', TC.Get, 1);
  o.Free;
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CLASSCTORWARN OK');
end.
