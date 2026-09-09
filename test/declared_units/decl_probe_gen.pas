unit decl_probe_gen;
{ THE OBJFPC SPELLING, and it is here because it fails differently from the
  Delphi one. objfpc writes `generic TFoo<T, S> = class`, and there is no
  tkGeneric -- `generic` reaches the declaration scan as a plain identifier, so
  it CONSUMES the slot the scan was holding for a type name and TGenFpc is never
  examined at all.

  That made every objfpc generic answer False, and the row that asks
  `declared(TGenFpc)` -- which SHOULD be False -- agreed with fpc for entirely
  the wrong reason. A fixture with only that row would have certified the bug.
  The `<,>` row is the one that separates them. }
{$mode objfpc}{$H+}
interface
type
  generic TGenFpc<T, S> = class
  end;
implementation
end.
