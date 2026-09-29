program test_an_owning_object_list_destroys_its_items;
{ contnrs' TFPObjectList(OwnsObjects) frees items through TObject(p).Free in
  the UNIT, which skipped the override's destructor, so every item's owned
  TInner leaked. Leak census row: 3000 items in batches of 10; `keep` leaks
  the inners on purpose as the control.
  bug-a-free-on-a-tobject-in-a-unit-skips-the-overridden-destructor }
{$mode objfpc}
uses contnrs;
type
  TInner = class
    Buf: array of Byte;
  end;
  TItem = class
    Inner: TInner;
    constructor Create;
    destructor Destroy; override;
  end;
var
  KeepInner: Boolean = False;
constructor TItem.Create;
begin
  Inner := TInner.Create;
  SetLength(Inner.Buf, 64);
end;
destructor TItem.Destroy;
begin
  if not KeepInner then Inner.Free;
  inherited Destroy;
end;
var
  L: TFPObjectList;
  i, round: Integer;
begin
  KeepInner := (ParamCount > 0) and (ParamStr(1) = 'keep');
  L := TFPObjectList.Create(True);
  for round := 1 to 300 do
  begin
    for i := 1 to 10 do L.Add(TItem.Create);
    L.Clear;
  end;
  L.Free;
  writeln('ok');
end.
