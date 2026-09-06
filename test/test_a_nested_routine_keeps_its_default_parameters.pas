{ A nested routine that CAPTURES enclosing state is lambda-lifted to top level
  and given the captures as extra parameters, and the call sites are rewritten
  to pass them. They used to be appended at the TAIL -- which is exactly where
  an omitted DEFAULT parameter has to go, so the two collided:

    procedure SetMode(const M: Integer; ...; UseOtherwise: Boolean = True);
    SetMode(1, [0], False, [3]);        { 4 of 6 written }

  became SetMode(1, [0], False, [3], Self, Param) -- six actuals against
  (own0..own5, Self, Param) -- and the call was REFUSED, so this row is a
  compile check as much as a value check. fcl-passrc's pscanner.pp HandleMode
  is this shape and it accounted for seven of its fourteen walls.

  Captures now lead. The three rows below are the three splice paths, which are
  three separate pieces of code: an ordinary call from the enclosing body, a
  SELF-RECURSIVE call (which passes __nestself rather than Self), and a call
  with no argument list at all. Each asserts a VALUE and not just a clean
  compile -- a capture landing on a defaulted slot binds a wrong value as
  readily as it refuses.
  bug-p-a-nested-routine-with-default-parameters-loses-them-to-its-captures }
{$mode objfpc}
program test_a_nested_routine_keeps_its_default_parameters;
type
  TBS = set of 0..7;
  TC = class
    F: Integer;
    procedure Handle(const Param: String);
  end;

procedure TC.Handle(const Param: String);
var acc: Integer;

  { every arity between "all defaults omitted" and "all written" }
  procedure Show(const LangMode: Integer;
    const NewSwitches: TBS; IsDelphi: Boolean;
    const AddSwitches: TBS = [];
    const RemoveSwitches: TBS = [];
    UseOtherwise: Boolean = True
    );
  begin
    WriteLn('lm=', LangMode, ' isd=', IsDelphi, ' uo=', UseOtherwise,
            ' add=', 3 in AddSwitches, ' rem=', 5 in RemoveSwitches,
            ' cap=', Param, F);
  end;

  { self-recursive AND defaulted: the __nestself splice }
  procedure Down(n: Integer; step: Integer = 1);
  begin
    acc := acc + n * F;
    if n > 0 then Down(n - step);
  end;

  { a sibling calling a capturing routine that has a default }
  procedure Kick(tag: String = 'k');
  begin
    Down(2);
    WriteLn(tag, ' acc=', acc, ' p=', Param);
  end;

  { ...and a call with no argument list at all }
  procedure Bare;
  begin
    acc := acc + 100;
    Kick;
  end;

begin
  Show(1, [0], False, [3]);
  Show(2, [0], True, [3], [5]);
  Show(3, [0], True, [3], [5], False);
  Show(4, [0], False);
  acc := 0;
  Down(3);
  Kick('one');
  Bare;
end;

var c: TC;
begin c := TC.Create; c.F := 2; c.Handle('P'); end.
