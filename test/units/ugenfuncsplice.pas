unit ugenfuncsplice;
{ A generic ROUTINE in a unit, plus a type the unit declares, so a specializing
  program can be measured BOTH ways: on a type of its own (the defect) and on a
  type of the unit's (the control that always worked).
  bug-p-an-imported-generic-routine-is-spliced-before-the-programs-own-type-section }
{$mode objfpc}
interface

type
  TInUnit = record Tag: LongInt; end;

generic function TagOf<T>(const a: T): LongInt;

implementation

generic function TagOf<T>(const a: T): LongInt;
begin
  Result := a.Tag;
end;

end.
