{ THE TRAILING UNIT, AND ITS ONLY JOB IS TO HAVE AN IMPLEMENTATION `uses`.

  It takes no part in the cycle. It is named AFTER ucyctail_a in ucyctail_b's
  implementation clause, and loading it re-enters ParseUnitImplSection -- which
  is what used to clear the pending park that ucyctail_a had just set. A unit
  with no implementation `uses` of its own does NOT reproduce: the clearing
  happens in the `tkUses` arm, so the clause below is the active ingredient and
  must not be deleted as unused.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
unit ucyctail_t;
interface

function TailHelper(x: LongInt): LongInt;

implementation

uses sysutils;                    { <- the active ingredient: see the header }

function TailHelper(x: LongInt): LongInt;
begin
  TailHelper := x + StrToInt('1');
end;

end.
