program test_dce_cost_is_a_differential_not_a_subtree_sum;
{ --dce-cost=<substr> must report what a VMT/RTTI slot COSTS, which is not the
  same number as what it REACHES. This is the case that separates the two, and
  it is arranged so that no implementation summing a subtree can pass it.

  THE SHAPE. TThing.Unreached is virtual and nothing calls it, so its VMT slot
  is a DCE root. It reaches three bodies:

      Unreached -> OnlyDead      nothing else reaches OnlyDead
      Unreached -> Used          but Used has its own VMT slot
      Unreached -> SharedHelper  and TThing.Used reaches SharedHelper too

  Withholding Unreached slot kills exactly TWO bodies, Unreached and OnlyDead.
  A subtree sum over what that slot reaches would say THREE or four. The
  one-body difference is the assertion, and it is asserted as a COUNT rather
  than as bytes so it does not drift when a body code changes.

  ROW 2 IS A NAME THAT IS NOT A SLOT, AND IT MUST BE ZERO. SharedHelper is
  live and reached from two places, and --dce-cost=SharedHelper answers
  0B in 0 bodies, because the flag withholds VMT SLOTS and not bodies. Without
  this row an implementation that charged "everything reachable from this name"
  would pass row 1 by luck on some arrangement; with it, it cannot.

  ROW 3 IS A FACT THIS FIXTURE MEASURED AND I HAD ASSUMED THE OPPOSITE OF.
  The first draft asserted --dce-cost=TThing.Used would be ZERO, reasoning that
  Used is "called directly" from the main body and from Unreached, so its slot
  would be redundant. It is 49B in 1 body. A call to a VIRTUAL method is a
  dispatch THROUGH the slot, not a second route to the body, so for a virtual
  method the slot is the only edge there is and withholding it always costs the
  body. The prediction was written from an argument and the measurement
  disagreed; the row is kept with the measured value because the assumption is
  an easy one to make twice.

  THE NEGATIVE CONTROL WAS RUN, AND IT IS THE ONLY THING THAT SHOWS ROW 1 IS
  ABOUT SHARING RATHER THAN ABOUT ARITHMETIC. Delete the SharedHelper call from
  TThing.Used, so SharedHelper sits uniquely behind Unreached, and the same
  command answers 3 bodies (231B) instead of 2 (160B). Nothing else changes.
  Without that run, "2" is just a number the fixture happens to produce.

  The FIRST attempt at that control was itself wrong and answered 2, which
  reads as the fixture being broken: a `sed` on `^  SharedHelper;$` was meant
  to cut the call in Used and did not cut the one it was aimed at. A control
  that edits the wrong line produces a frightening answer about the thing under
  test, so build the control by naming the whole procedure body, not by
  matching a line that appears twice.

  Measured 2026-09-22 at binary 48f69d2d285d, x86-64 default flags:
  Unreached 160B/2, TThing.Used 49B/1, SharedHelper 0B/0. The Makefile asserts
  the COUNTS; the byte figures are recorded here and are expected to drift.

  WHY THIS EXISTS AT ALL, in one line: on the nilpy-c3 demo the two numbers
  disagree by 8.6x on the largest candidate and INVERT the ranking of the top
  three, so choosing what to work on from the --dce-why table sends you to the
  wrong method.
  feature-a-unreferenced-class-rtti-keeps-every-method-alive }

type
  TThing = class
    constructor Create;
    procedure Used; virtual;
    procedure Unreached; virtual;
  end;

var
  Sink: Integer;

procedure SharedHelper;
{ Reached from BOTH arms. Must survive withholding Unreached's slot -- that is
  the body a subtree sum would wrongly charge to it. }
begin
  Sink := Sink + 1;
  Sink := Sink * 3;
  Sink := Sink - 2;
end;

procedure OnlyDead;
{ Reached ONLY from Unreached. Must die with it. }
begin
  Sink := Sink + 7;
  Sink := Sink * 5;
  Sink := Sink - 4;
end;

constructor TThing.Create;
begin
end;

procedure TThing.Used;
begin
  SharedHelper;
end;

procedure TThing.Unreached;
begin
  { SharedHelper LAST on purpose. It is the element the assertion is about --
    the body that must SURVIVE -- and CLAUDE.md's rule is that the position of
    the interesting element in an ordered list is a variable nobody varies, so
    a fixture that puts it first certifies the arrangement that happens to
    pass. Withholding this slot must kill two bodies from whichever position
    they are called in. }
  OnlyDead;
  Used;
  SharedHelper;
end;

var
  t: TThing;

begin
  Sink := 0;
  t := TThing.Create;
  t.Used;
  WriteLn('SINK ', Sink);
end.
