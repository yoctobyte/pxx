program test_forin_member_access;

{ `for x in <member-access lvalue>` — the for-in source is a qualified
  expression (obj.field, a.b.field), not a bare name. The source is parsed as a
  general lvalue node and deep-copied per use by the node-based loop builder so
  the Length bound and element access don't alias one node. Covers a dyn-array
  field reached through one and two levels of member access, plus a string field
  reached through member access (char iteration). }

{$define PXX_MANAGED_STRING}

type
  TItem = class
    Id: Integer;
  end;

  TBag = class
    Items: array of TItem;
    Tag: AnsiString;
  end;

  TGame = class
    Bag: TBag;
    function SumIds: Integer;       { for it in Bag.Items — one level }
    function CountTagUpper: Integer; { for c in Bag.Tag — string via member }
  end;

function TGame.SumIds: Integer;
var it: TItem;
begin
  Result := 0;
  for it in Bag.Items do Result := Result + it.Id;
end;

function TGame.CountTagUpper: Integer;
var c: Char;
begin
  Result := 0;
  for c in Bag.Tag do
    if (c >= 'A') and (c <= 'Z') then Result := Result + 1;
end;

var
  g: TGame;
  a, b: TItem;
  it: TItem;
  outer: Integer;
begin
  g := TGame.Create;
  g.Bag := TBag.Create;
  SetLength(g.Bag.Items, 2);
  a := TItem.Create; a.Id := 30; g.Bag.Items[0] := a;
  b := TItem.Create; b.Id := 12; g.Bag.Items[1] := b;
  g.Bag.Tag := 'aBxYz';

  Writeln(g.SumIds);          { 42  (method, implicit-Self member access) }
  Writeln(g.CountTagUpper);   { 2   (B, Y) }

  { member access from the main block (two levels: g.Bag.Items) }
  outer := 0;
  for it in g.Bag.Items do outer := outer + it.Id;
  Writeln(outer);             { 42 }
end.
