unit uclsalias; {$mode objfpc}
interface
type
  generic TEnum<T> = class(TObject)
    V: T;
    function GetCurrent: T;
  end;
  generic TList7<T> = class(TObject)
  type
    TEnumSpec = specialize TEnum<T>;
  public
    function Mk(const x: T): TEnumSpec;
  end;
  TRed  = class(TObject) R: LongInt; end;
  TBlue = class(TObject) B: ShortString; end;
implementation
function TEnum.GetCurrent: T; begin Result := V; end;
function TList7.Mk(const x: T): TEnumSpec; begin Result := TEnumSpec.Create; Result.V := x; end;
end.
