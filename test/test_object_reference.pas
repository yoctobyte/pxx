program test_object_reference;

{ `object` — a rooted object-reference type: pointer-sized, holds ANY class
  instance, no specific class bound. Widening assignment from any class ref;
  member access requires an explicit cast to a concrete class. }

type
  TAnimal = class
    FName: AnsiString;
    constructor Create(n: AnsiString);
    function Speak: AnsiString; virtual;
  end;
  TDog = class(TAnimal)
    function Speak: AnsiString; override;
  end;
  TCat = class(TAnimal)
    function Speak: AnsiString; override;
  end;
  THolder = record
    Item: object;          { object as a record field }
    Kind: Integer;
  end;

constructor TAnimal.Create(n: AnsiString);
begin
  FName := n;
end;

function TAnimal.Speak: AnsiString;
begin
  Speak := '...';
end;

function TDog.Speak: AnsiString;
begin
  Speak := FName + ': woof';
end;

function TCat.Speak: AnsiString;
begin
  Speak := FName + ': meow';
end;

{ object as a parameter; cast back inside }
function Describe(o: object): AnsiString;
begin
  Describe := TAnimal(o).Speak;
end;

var
  o: object;
  d: TDog;
  c: TCat;
  zoo: array of object;    { mixed instances }
  h: THolder;
  i: Integer;
begin
  d := TDog.Create('Rex');
  c := TCat.Create('Tom');

  o := d;                        { widening: class -> object }
  writeln(Describe(o));          { Rex: woof }
  o := c;
  writeln(TAnimal(o).Speak);     { cast root + virtual dispatch: Tom: meow }

  SetLength(zoo, 2);
  zoo[0] := d;
  zoo[1] := c;
  for i := 0 to 1 do
    writeln(Describe(zoo[i]));

  h.Item := d;
  h.Kind := 1;
  writeln(TDog(h.Item).Speak);   { concrete cast from a field }

  o := nil;
  if o = nil then writeln('nil ok');

  writeln('OK');
end.
