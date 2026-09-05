{ The mode-Delphi surface of a generic routine, in a UNIT.

  This is the ONE shape that separates a declaration from a use in the Delphi
  spelling: `function DTwice<T>(...)` in this unit's interface AND in its
  implementation is spelled token-for-token like a use site, and a unit's tokens
  are APPENDED after the importing program's, so the program's own
  specialization sweep runs forward straight over these two headers. Before the
  declaration guard in SpecializeInlineGenericFuncUses they were rewritten to
  `DTwice_T` and compiled as real routines: `unknown type: T`, reported inside
  this file, from a defect in the program's sweep.
  feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling }
unit ugfdelphi;
{$mode delphi}
interface

function DTwice<T>(a: T): T;

implementation

function DTwice<T>(a: T): T;
begin
  Result := a + a;
end;

end.
