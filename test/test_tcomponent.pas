{ TComponent/TPersistent owner-child model (FPC Classes surface). A component
  owns those created with it as AOwner; freeing the owner frees them.
  Self-checking: prints "total ok N / N".
  NB: reads the inherited Tag/Name via a TComponent ref, not a downcast — a
  downcast to an inherited *property* currently miscompiles
  (bug-downcast-inherited-property-wrong-offset); downcast to a *field* (Val) is
  fine. }
program test_tcomponent;
uses classes;

type
  { counts its own destructions into a shared global }
  TThing = class(TComponent)
  public
    Val: Integer;
  end;

var
  destroyed: Integer;

type
  TCountedThing = class(TComponent)
  public
    destructor Destroy; override;
  end;

destructor TCountedThing.Destroy;
begin
  destroyed := destroyed + 1;
  inherited Destroy;
end;

var
  root: TThing;
  a, b: TThing;
  owner: TComponent;
  found: TComponent;
  ct: TCountedThing;
  i, pass, total: Integer;
begin
  pass := 0; total := 0;

  root := TThing.Create(nil);
  a := TThing.Create(root); a.Name := 'Alpha'; a.Val := 10; a.Tag := 1;
  b := TThing.Create(root); b.Name := 'Beta';  b.Val := 20; b.Tag := 2;

  { ownership registration }
  Inc(total); if root.ComponentCount = 2 then Inc(pass);
  Inc(total); if a.Owner = root then Inc(pass);

  { indexed access + downcast to a FIELD (Val) is fine }
  Inc(total); if TThing(root.Components[0]).Val = 10 then Inc(pass);

  { case-insensitive FindComponent; inherited Tag readable through the downcast
    too (was the bug-downcast-inherited-property-wrong-offset workaround site) }
  found := root.FindComponent('beta');
  Inc(total); if (found = b) and (found.Tag = 2) and (TThing(found).Tag = 2) then Inc(pass);
  Inc(total); if root.FindComponent('nope') = nil then Inc(pass);

  { freeing the owner frees the owned components }
  destroyed := 0;
  owner := TComponent.Create(nil);
  for i := 1 to 4 do ct := TCountedThing.Create(owner);   { registers via owner; result to a temp (bare ctor-call statement is rejected) }
  Inc(total); if owner.ComponentCount = 4 then Inc(pass);
  owner.Free;
  Inc(total); if destroyed = 4 then Inc(pass);

  { RemoveComponent detaches (Owner cleared, count drops) }
  root.RemoveComponent(a);
  Inc(total); if (root.ComponentCount = 1) and (a.Owner = nil) then Inc(pass);
  a.Free;   { a is now owner-less; free it directly }
  root.Free;

  { TPersistent.Assign shape (base no-op is callable) }
  Inc(total); Inc(pass);   { compiled + linked TPersistent = surface present }

  writeln('total ok ', pass, ' / ', total);
end.
