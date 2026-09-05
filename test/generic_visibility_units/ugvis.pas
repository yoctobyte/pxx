unit ugvis; {$MODE DELPHI}
{ Two templates, one per section. The INTERFACE one is nameable by importers;
  the IMPLEMENTATION one is private to this unit and must not be.
  Regression cover for bug-p-a-generic-template-declared-in-a-units-
  implementation-is-visible-to-its-importers. }
interface
type TVisible<T> = record V: T; end;
function OwnUse: Integer;          { the unit's OWN use of its private template }
implementation
type THidden<T> = record V: T; end;
function OwnUse: Integer;
var p: THidden<Integer>;
begin p.V := 5; Result := p.V; end;
end.
