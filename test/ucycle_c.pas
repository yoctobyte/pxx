{ The THIRD unit: ucycle_c's implementation names ucycle_a AND ucycle_b in ONE
  clause, both still loading. With only two units a clause names exactly one
  open unit, so this is the first shape where "which one do we wait for" is a
  question at all.

  IT PASSES UNDER BOTH ANSWERS, and that was measured rather than assumed --
  the comment here first claimed it discriminated and it does not. Waiting on
  the inner unit drains this section too early, the replay re-walks the clause
  from the head of the section, ucycle_a is still open, and the section parks
  again on it. Correct either way; the wrong answer costs a table slot per hop,
  which is a scale problem and not a visible one.

  So what this file actually pins is the CHAIN: a cycle two levels deep, with a
  type, a const and a routine crossing it, exercising re-entry into a section
  whose own `uses` names more than one thing.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
unit ucycle_c;
interface

function CReadsBoth(x: LongInt): LongInt;

implementation

uses ucycle_a, ucycle_b;          { <- two open units in ONE clause }

function CReadsBoth(x: LongInt): LongInt;
var
  r: TCycleRec;                   { a type from A, the outer one }
begin
  r.Tag := ACONST + BCall(x);     { a const from A and a routine from B }
  CReadsBoth := r.Tag;
end;

end.
