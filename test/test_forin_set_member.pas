{ `for x in <qualified set-valued lvalue>` — a `set of <enum>` reached through
  obj.field / Self.field / a nested member access. The node-based for-in source
  classifier recovers the field's set element enum range and reuses the
  membership-scan desugar (iterate ordinals, run body when `ord in setExpr`).
  Regression for bug-forin-qualified-set-member-source (adventure Player.Spells). }
program test_forin_set_member;

type
  TSpell = (spFire, spIce, spHeal, spBolt, spDoom);
  TSpellSet = set of TSpell;
  TPlayer = class
    Spells: TSpellSet;
  end;
  TGame = class
    Player: TPlayer;
  end;

var
  g: TGame;
  sp: TSpell;
begin
  g := TGame.Create;
  g.Player := TPlayer.Create;
  g.Player.Spells := [spFire, spHeal, spDoom];

  { qualified member-access source }
  for sp in g.Player.Spells do
    Writeln('spell=', Ord(sp));          { 0 / 2 / 4 in ordinal order }

  { empty set yields nothing }
  g.Player.Spells := [];
  for sp in g.Player.Spells do
    Writeln('never=', Ord(sp));

  Writeln('done');
end.
