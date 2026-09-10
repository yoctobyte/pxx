{ Half of the cycle for test_p_a_unit_cycle_through_an_implementation_uses.pas.

  THE ORDER IS THE WHOLE POINT and it is why the declarations sit BELOW the
  `uses`: `ucycle_b`'s implementation asks for `HookProc` and `TCycleRec` at a
  moment when this unit's interface has only been parsed as far as its own
  `uses` line. Moving these above it would make the test pass for a reason
  that has nothing to do with the defect.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
unit ucycle_a;
interface
uses ucycle_b;                    { <- the interface half of the cycle }

type
  TCycleRec = record
    Tag: LongInt;
  end;

var
  HookProc: procedure(i: LongInt);

function ACallsB(x: LongInt): LongInt;
const
  ACONST = 41;

implementation

procedure DefaultHook(i: LongInt);
begin
  WriteLn('hook ', i);
end;

function ACallsB(x: LongInt): LongInt;
begin
  ACallsB := BCall(x);            { the other direction, through B's interface }
end;

begin
  HookProc := @DefaultHook;
end.
