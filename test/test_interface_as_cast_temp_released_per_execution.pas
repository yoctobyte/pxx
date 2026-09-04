program TestInterfaceAsCastTempReleasedPerExecution;
{ bug-a-an-interface-as-cast-retains-on-every-execution-and-releases-once-per-scope

  `obj as IFoo` materialises the interface value into a hidden temp and AddRefs
  it, because a QueryInterface returns an owning reference. The temp is memoised
  in ASTLiftedVar -- ONE slot per cast SITE, not per execution -- so a cast
  inside a loop retained a different object into the same word every trip while
  only the last one was ever released. Everything but the last leaked, and its
  DESTRUCTOR NEVER RAN.

  Measured against the FPC oracle on this exact source:

    row                          FPC   pxx before   pxx after
    5 casts in the main body       4            0           4
    3 casts inside a procedure     3            1           3
    5 objects, no cast at all      5            5           5

  ROW THREE IS THE CONTROL AND IT MUST NOT MOVE. The implicit class->interface
  coercion goes down the ordinary managed-assignment path, which already
  released the slot's previous value; it was correct before this fix and is the
  row that says the harness is measuring destruction at all. Without it, "5 5 5"
  and "0 1 5" are equally consistent with a destructor that never increments.

  Main-body 4-of-5 is not an off-by-one: the cast temp legitimately still holds
  the fifth object when the count is printed, and is released at end of main.
  FPC answers 4 for the same reason. `p := nil` before the writeln is what makes
  the OTHER four accountable -- without it the loop variable would hold one too
  and the row could not distinguish 4 from 3.

  A leak assertion alone would not have caught this half: the objects are
  reachable-and-never-freed, so an output test passes and only a destructor with
  a side effect makes it visible. The census agrees (0.973 blocks per iteration
  before, flat after) but the destructor count is the claim. }

type
  IThing = interface ['{A1B2C3D4-0001-0002-0003-0004000500AA}']
    function Val: Integer;
  end;
  TThing = class(TInterfacedObject, IThing)
    k: Integer;
    function Val: Integer;
    destructor Destroy; override;
  end;

var destroyed: Integer;

function TThing.Val: Integer; begin Val := k; end;
destructor TThing.Destroy; begin Inc(destroyed); inherited Destroy; end;

procedure Loop3;
var q: IThing; j: Integer;
begin
  for j := 1 to 3 do q := TThing.Create as IThing;
end;

var i: Integer; p: IThing;
begin
  destroyed := 0;
  for i := 1 to 5 do p := TThing.Create as IThing;
  p := nil;
  writeln('mainbody: created 5 destroyed ', destroyed);

  destroyed := 0;
  Loop3;
  writeln('in-proc:  created 3 destroyed ', destroyed);

  destroyed := 0;
  for i := 1 to 5 do p := TThing.Create;
  p := nil;
  writeln('no cast:  created 5 destroyed ', destroyed);
end.
