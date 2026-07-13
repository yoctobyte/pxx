{ PROPERTY REDECLARATION: `property Items;` -- re-expose an inherited property by naming
  it alone, optionally adding a directive.

  fpjson's TJSONArray writes `property Items;default;` to make the inherited indexed
  property the class's DEFAULT array property, so `arr[i]` routes through it.

  The redeclaration is re-registered on the descendant with the ancestor's accessors
  copied, rather than just letting the lookup find the ancestor's row -- the whole point of
  the redeclaration is usually to CHANGE something (here, `default`), and that change must
  not be written onto the ancestor. }
program test_property_redecl_b283;
type
  TBase = class
  private
    FItems: array[0..9] of Integer;
    function GetItem(i: Integer): Integer;
    procedure SetItem(i, v: Integer);
  public
    property Items[i: Integer]: Integer read GetItem write SetItem;
  end;
  { redeclare the inherited property and make it the DEFAULT array property }
  TChild = class(TBase)
  public
    property Items; default;
  end;
function TBase.GetItem(i: Integer): Integer;
begin Result := FItems[i]; end;
procedure TBase.SetItem(i, v: Integer);
begin FItems[i] := v; end;
var
  b: TBase;
  c: TChild;
begin
  b := TBase.Create;
  b.Items[2] := 7;
  writeln('base explicit: ', b.Items[2]);
  c := TChild.Create;
  c.Items[3] := 9;                { the redeclared property still works by name }
  writeln('child explicit: ', c.Items[3]);
  c[4] := 11;                     { ...and now as the DEFAULT array property }
  writeln('child default: ', c[4]);
  writeln('child default read of 3: ', c[3]);
end.
