{ The other half. Its INTERFACE names nothing from ucycle_a -- that is what
  makes the cycle legal Pascal rather than a genuine circular reference: the
  cycle is closed through the IMPLEMENTATION uses below, which is the entire
  reason the language splits the clause in two.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
unit ucycle_b;
interface

function BCall(x: LongInt): LongInt;
function BUsesAType(x: LongInt): LongInt;
function BReadsAConst: LongInt;

implementation

uses ucycle_a;                    { <- the implementation half of the cycle }

function BCall(x: LongInt): LongInt;
begin
  HookProc(x);                    { a VAR from A's interface }
  BCall := x + 1;
end;

function BUsesAType(x: LongInt): LongInt;
var
  r: TCycleRec;                   { a TYPE from A's interface }
begin
  r.Tag := x * 2;
  BUsesAType := r.Tag;
end;

function BReadsAConst: LongInt;
begin
  BReadsAConst := ACONST;         { a CONST from A's interface }
end;

end.
