unit utvinline;
{ The ticket's own spelling: a `threadvar` in a unit's IMPLEMENTATION section,
  read by a leaf function small enough for the -O2 inliner to retain. That is
  the shape that crashed or read 0 before the retention guard in
  InlineExprSimple -- see bug-a-a-threadvar-in-a-units-implementation-section-
  silently-reads-zero. The INTERFACE spelling is here too because the ticket
  originally reported it as the working one and it is not: both spellings reach
  the same retention door, and the section was never the variable. }

interface

threadvar
  ifcCounter: LongInt;          { the INTERFACE spelling }

procedure Bump;                  { writes the implementation-section one }
function GotViaFunction: LongInt;
procedure GotViaProcedure(var o: LongInt);
function GotIfc: LongInt;

implementation

threadvar
  implCounter: LongInt;         { the IMPLEMENTATION spelling }

procedure Bump;
begin
  implCounter := implCounter + 7;
end;

function GotViaFunction: LongInt;
begin
  Result := implCounter;
end;

procedure GotViaProcedure(var o: LongInt);
{ The control INSIDE the unit: a procedure is not a retention candidate, so
  this row was CORRECT the whole time the function beside it was wrong. If a
  future change breaks the rewrite itself rather than the inliner, this row
  goes red too and tells the two apart. }
begin
  o := implCounter;
end;

function GotIfc: LongInt;
begin
  Result := ifcCounter;
end;

end.
