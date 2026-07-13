{ `for F in Data do` where the container is a PROPERTY, not a variable.

  The enumerator path (GetEnumerator / MoveNext / Current) existed, but keyed on the container
  having a SYMBOL -- so it only ever accepted a bare variable. fcl-json's own test suite writes
  `For F in Data do`, Data being a property.

  A container that is not a bare variable is now parsed as an EXPRESSION and materialised into
  a hidden local, which the existing enumerator loop then drives. The container is evaluated
  exactly ONCE -- what FPC does, and what a getter with side effects requires.

  The QUALIFIED source (`for x in o.Bag`) is a DIFFERENT path again -- it is grabbed earlier, by
  the qualified-member-access branch, which only ever knew arrays, strings and sets. It now
  materialises a class container the same way. Both are asserted below.

  The plain-array case is here to pin that the bare-variable fast path is untouched. }
program test_forin_property_b295;
type
  TEnum = class
    FI: Integer;
    function MoveNext: Boolean;
    function GetCurrent: Integer;
    property Current: Integer read GetCurrent;
  end;
  TBag = class
    function GetEnumerator: TEnum;
  end;
  TOwner = class
    FBag: TBag;
    property Bag: TBag read FBag;
    procedure Go;
  end;
var g: array[0..2] of Integer;
function TEnum.MoveNext: Boolean;
begin Inc(FI); Result := FI <= 2; end;
function TEnum.GetCurrent: Integer;
begin Result := g[FI]; end;
function TBag.GetEnumerator: TEnum;
begin Result := TEnum.Create; Result.FI := -1; end;
{ implicit-Self property -- the shape fcl-json's own suite uses (`For F in Data do`) }
procedure TOwner.Go;
var x: Integer;
begin
  for x in Bag do write(x, ' ');
  writeln;
end;
var o: TOwner; a: array[0..2] of Integer; x: Integer;
begin
  g[0] := 1; g[1] := 2; g[2] := 3;
  o := TOwner.Create;
  o.FBag := TBag.Create;
  o.Go;
  { QUALIFIED source: a property reached through another object }
  for x in o.Bag do write(x, ' ');
  writeln;
  { plain array for-in must still work }
  a[0] := 7; a[1] := 8; a[2] := 9;
  for x in a do write(x, ' ');
  writeln;
end.
