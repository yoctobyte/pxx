{ The other half of the mutually circular pair; Bump differs from ucircgena's so
  a body materialised against the wrong template prints a different number. }
unit ucircgenb;
{$mode objfpc}{$H+}
interface
type
  generic TGenB<T> = class
    class function Bump(v: T): T;
    class function Who: ShortString;
  end;
  TDrvB = class
    class procedure Run;
  end;
implementation
uses ucircgena;
type
  TGenALong = specialize TGenA<LongInt>;
class procedure TDrvB.Run;
begin
  WriteLn('b-uses-a ', TGenALong.Bump(20), ' ', TGenALong.Who);
end;
class function TGenB.Bump(v: T): T;
begin
  Result := v + 2;
end;
class function TGenB.Who: ShortString;
begin
  Result := Self.ClassName;
end;
end.
