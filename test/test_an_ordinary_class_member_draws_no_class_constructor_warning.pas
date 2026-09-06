program test_an_ordinary_class_member_draws_no_class_constructor_warning;
{ bug-p-a-class-constructor-is-accepted-and-never-runs -- THE NEGATIVE CONTROL.

  The warning is emitted from the member-loop terminus, which is also where
  `class var` and every other unrecognised `class X` opener lands. A guard
  written one token too wide would fire on all of them and nobody would notice,
  because a warning does not fail a build. So this file is every OTHER `class`
  opener the parser sees, in both a class body and a record body and once
  through a generic, and the Makefile asserts its compile log is silent.

  Drawn from the population the question is about: these are the spellings that
  reach the same arm, not a sample of unrelated code. }
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
  if fails = 0 then WriteLn('NOCLASSCTORWARN OK');
end.
