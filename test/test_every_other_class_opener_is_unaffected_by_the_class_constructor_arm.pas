program test_every_other_class_opener_is_unaffected_by_the_class_constructor_arm;
{ bug-p-a-class-constructor-is-accepted-and-never-runs -- THE NEGATIVE CONTROL.

  The `class X` opener in each member loop is a hand-maintained list, and the
  fix added an arm to it. An arm written one token too wide swallows a
  neighbour: `class var`, `class const`, `class property`, `class procedure`,
  `class function` and the generic spellings all reach the same test, and a
  member consumed by the wrong arm does not fail to compile -- it compiles into
  something else.

  This file is every OTHER `class` opener the parser sees, in a class body, a
  record body and once through a generic, and it RUNS them: drawn from the
  population the question is about, not a sample of unrelated code.

  It was the control for the interim WARNING (asserting the compile log was
  silent) and that assertion is retired with the warning. A log that can no
  longer contain the string is a guard that cannot fail; what the rows below
  assert instead is that each spelling still does its job. }
type
  TC = class
    class var N: Integer;
    class const K = 3;
    class procedure P;
    class function F: Integer;
    class property Q: Integer read N write N;
  end;

  generic TG<T> = class
    class var GN: Integer;
    class function G: Integer;
  end;

  TR = record
    class var M: Integer;
    class function H: Integer; static;
    class procedure S(v: Integer); static;
    class property RP: Integer read M write M;
  end;

  TIntG = specialize TG<Integer>;

class procedure TC.P; begin TC.N := TC.N + 1; end;
class function TC.F: Integer; begin F := TC.N + TC.K; end;
class function TG.G: Integer; begin G := GN + 2; end;
class function TR.H: Integer; begin H := TR.M; end;
class procedure TR.S(v: Integer); begin TR.M := v; end;

var
  fails: Integer;

procedure Check(const what: AnsiString; got, want: Integer);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  TC.N := 0;
  TC.P;
  Check('class procedure', TC.N, 1);
  Check('class function reads class const', TC.F, 4);
  Check('class property', TC.Q, 1);
  Check('generic class function', TIntG.G, 2);
  TR.S(9);
  Check('record class procedure', TR.H, 9);
  Check('record class property', TR.RP, 9);
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CLASSOPENERS OK');
end.
