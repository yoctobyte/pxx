{ ONE-SIDED circular pair: c declares the template and uses d; d specializes it
  and uses c. Only ONE side specializes -- the narrower boundary, and the one
  the ticket's "each specializes the other's" did not name. }
unit ucircgenc;
{$mode objfpc}{$H+}
interface
type
  generic TGenC<T> = class
    class function Bump(v: T): T;
  end;
  TDrvC = class
    class procedure Run;
  end;
implementation
uses ucircgend;
class procedure TDrvC.Run;
begin
  WriteLn('c-plain ', TDrvD.Peek);
end;
class function TGenC.Bump(v: T): T;
begin
  Result := v + 3;
end;
end.
