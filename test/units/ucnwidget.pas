unit ucnwidget;
{ A unit whose NAME a class in ucncollide reuses.
  bug-a-a-class-named-after-a-used-unit-cannot-be-constructed-from-outside-that-unit }
{$MODE PXX}
interface
type TThing = record v: Integer; end;
implementation
end.
