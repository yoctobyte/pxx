unit uxgmid;
{$mode objfpc}
{ A UNIT calling ANOTHER unit's generic method. There is no later point in this
  unit from which a forward sweep would reach its own body -- but its own
  `uses uxgm` is before it, which is the window the deferred sweep runs in. }
interface
uses uxgm;
function ViaUnit: Integer;
implementation
function ViaUnit: Integer;
var t: TXG;
begin
  t := TXG.Create;
  ViaUnit := t.specialize Add<Integer>(20, 22);
end;
end.
