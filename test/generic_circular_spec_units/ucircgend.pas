{ d specializes c's template from its own implementation section; c specializes
  nothing. }
unit ucircgend;
{$mode objfpc}{$H+}
interface
type
  TDrvD = class
    class function Peek: LongInt;
  end;
implementation
uses ucircgenc;
type
  TGenCLong = specialize TGenC<LongInt>;
class function TDrvD.Peek: LongInt;
begin
  Result := TGenCLong.Bump(20);
end;
end.
