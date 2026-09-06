unit uxgm;
{$mode objfpc}
{ Generic METHODS declared in a unit and called from the importing program --
  the shape whose uses sit BEHIND the declaration in Tokens[], because a unit's
  tokens are appended after the program's. }
interface
type
  TXG = class
    generic function Add<T>(a, b: T): T;
    class generic function Twice<T>(a: T): T;
  end;
implementation
generic function TXG.Add<T>(a, b: T): T;
begin Result := a + b; end;
class generic function TXG.Twice<T>(a: T): T;
begin Result := a + a; end;
end.
