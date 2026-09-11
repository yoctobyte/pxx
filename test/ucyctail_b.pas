{ The implementation half, and THE ORDER OF THIS CLAUSE IS THE TEST.

  `ucyctail_a` closes the cycle; `ucyctail_t` follows it and has an
  implementation `uses` of its own. Loading ucyctail_t re-entered
  ParseUnitImplSection, which cleared the global CycleWaitUnit that ucyctail_a
  had just set, so this section never parked and every name below reported
  `undefined variable`. SWAPPING THE TWO NAMES MAKES IT PASS EVEN UNFIXED --
  that is what hid the defect through five reductions, all of which happened to
  put the cycle-closing unit last.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
unit ucyctail_b;
interface

function TailReadsConst: LongInt;
function TailReadsType(x: LongInt): LongInt;

implementation

uses ucyctail_a, ucyctail_t;      { <- cycle-closer FIRST, trailing unit AFTER }

function TailReadsConst: LongInt;
begin
  TailReadsConst := TAILCONST;    { a CONST from A's interface }
end;

function TailReadsType(x: LongInt): LongInt;
var
  r: TTailRec;                    { a TYPE from A's interface }
begin
  r.Tag := TailHelper(x);         { and a routine from the trailing unit }
  TailReadsType := r.Tag;
end;

end.
