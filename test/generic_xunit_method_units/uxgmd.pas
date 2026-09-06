unit uxgmd;
{$mode delphi}
{ The Delphi surface of the same thing -- no `generic` keyword anywhere. }
interface
type
  TXD = class
    function Add<T>(a, b: T): T;
  end;
implementation
function TXD.Add<T>(a, b: T): T;
begin Result := a + b; end;
end.
