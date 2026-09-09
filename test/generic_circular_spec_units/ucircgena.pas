{ Half of a MUTUALLY circular implementation-`uses` pair: each unit specializes
  the other's template. See
  bug-p-a-specialized-method-body-splices-into-an-illegal-place-under-circular-uses. }
unit ucircgena;
{$mode objfpc}{$H+}
interface
type
  generic TGenA<T> = class
    class function Bump(v: T): T;
    class function Who: ShortString;
  end;
  TDrvA = class
    class procedure Run;
  end;
implementation
uses ucircgenb;
type
  TGenBLong = specialize TGenB<LongInt>;
class procedure TDrvA.Run;
begin
  WriteLn('a-uses-b ', TGenBLong.Bump(20), ' ', TGenBLong.Who);
end;
class function TGenA.Bump(v: T): T;
begin
  Result := v + 1;
end;
class function TGenA.Who: ShortString;
begin
  Result := Self.ClassName;
end;
end.
