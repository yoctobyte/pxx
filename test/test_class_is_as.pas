program TestClassIsAs;
{$mode objfpc}
type
  TAnimal = class v: Integer; end;
  TDog = class(TAnimal) end;
  TCat = class(TAnimal) end;
  TPuppy = class(TDog) end;
var
  a, n: TAnimal;
  d: TDog;
begin
  d := TDog.Create;
  a := d;
  if a is TDog then writeln('is TDog') else writeln('not TDog');
  if a is TAnimal then writeln('is TAnimal') else writeln('not TAnimal');
  if a is TCat then writeln('is TCat') else writeln('not TCat');
  if a is TPuppy then writeln('is TPuppy') else writeln('not TPuppy');

  n := nil;
  if n is TAnimal then writeln('nil is') else writeln('nil not');

  { as: checked downcast, then use through a typed var }
  d := a as TDog;
  d.v := 42;
  writeln('v=', d.v);
  writeln('cast read=', (a as TDog).v);

  { a TPuppy is both a TDog and a TAnimal (transitive descendant) }
  a := TPuppy.Create;
  if a is TDog then writeln('puppy is TDog') else writeln('puppy not TDog');
  if a is TAnimal then writeln('puppy is TAnimal') else writeln('puppy not TAnimal');
  if a is TCat then writeln('puppy is TCat') else writeln('puppy not TCat');
end.
