unit unestspec;
{$mode objfpc}
{ A generic class whose own body declares a NESTED SPECIALIZATION and whose
  method body then uses it. This is `fgl.pp`'s TFPGList/TFPGListEnumeratorSpec
  shape, reduced to two classes and no corpus. }
interface
type
  generic TEnum<T> = class(TObject)
    V: T;
  end;

  generic TList<T> = class(TObject)
  type
    TEnumSpec = specialize TEnum<T>;
  public
    Item: T;
    function GetEnumerator: TEnumSpec;
  end;

  { A SECOND class whose nested type has the SAME NAME -- fgl declares
    TFPGListEnumeratorSpec three times, once per container. }
  { The type ARGUMENT itself, used inside the body -- fgl.pp:892 is
    `Result := T(FList.Items[FPosition]^)`, and after substitution that names a
    class the USING file declared. Same veto, same fix, different table entry. }
  generic TCastList<T> = class(TObject)
    Slot: Pointer;
    function GetCurrent: T;
  end;

  { ...and an INTERFACE type argument, which is fgl's `ifclist` row. Same
    table, same veto -- worth its own row only because "class" and "interface"
    are separate spellings and a fix could plausibly have covered one. }
  generic TIfList<T> = class(TObject)
    Slot: Pointer;
    function GetCurrent: T;
  end;

  generic TOther<T> = class(TObject)
  type
    TEnumSpec = specialize TEnum<T>;
  public
    Item: T;
    function GetEnumerator: TEnumSpec;
  end;
implementation
function TList.GetEnumerator: TEnumSpec;
begin
  Result := TEnumSpec.Create;
  Result.V := Item;
end;
function TCastList.GetCurrent: T;
begin
  Result := T(Slot);
end;
function TIfList.GetCurrent: T;
begin
  Result := T(Slot);
end;
function TOther.GetEnumerator: TEnumSpec;
begin
  Result := TEnumSpec.Create;
  Result.V := Item;
end;
end.
