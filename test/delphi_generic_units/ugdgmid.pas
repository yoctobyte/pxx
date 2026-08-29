unit ugdgmid;
{ A unit that USES another unit's template and specializes it itself -- the
  nested case. While ugdgbase was being parsed this unit's own resume position
  was live and sat in a region lexed earlier, so a desugar that edited the token
  stream below it resumed several tokens off ("unexpected token in a unit
  interface section"). Desugaring from the uses clause instead puts every edit
  above every live cursor by construction. }
{$MODE DELPHI}
interface

uses ugdgbase;

function MidVal: Integer;
function MidTag: Integer;

implementation

function MidVal: Integer;
var b: TBox<Integer>;
begin
  b := TBox<Integer>.Create;
  b.Val := 7;
  Result := b.Val;
end;

function MidTag: Integer;
var p: TPair<Integer, LongInt>;
begin
  p := TPair<Integer, LongInt>.Create;
  p.Tag := 9;
  Result := p.Tag;
end;

end.
