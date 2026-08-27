{ `class helper for <class>` — the CLASS flavour of the helper machinery that
  already backed `record helper for` and `type helper for`.

  What the rows pin (all three are fpc_diff_probe cases: class-helper-method,
  class-helper-shadowing, class-helper-inherited):

    a  a helper method reads the extended class's field unqualified
    b  a helper method SHADOWS an inherited virtual method NON-virtually — the
       helper wins at every static type that sees it, through a plain variable
       AND through a hard cast, and the VMT dispatch never runs
    c  an unqualified name inside a helper method binds to the extended type's
       members (TThingHelper.Tag2 calling bare Tag reaches TThing.Tag)
    d  `Self` inside a helper method IS the extended instance: Self.<field>
       reads the instance, and Self.<sibling helper method> comes back to the
       helper
    e  helper methods take parameters like any other method
    f  the receiver reached through a cast/selector chain, not just a bare
       variable — the two member-lookup loops in the Pascal parser both have to
       ask about helpers, and this is the one that goes through the second
    g  a helper for a BASE class serves a DESCENDANT receiver
    h  ...and the interleaving that makes g and b coexist: the search runs from
       the static type upward and asks, at each class, that class's helper
       BEFORE that class's own members. So a TDerived that overrides Name
       answers `d.Name` with its own override (TDerived has no helper of its
       own), while `b.Name` on the same object through a TBase variable answers
       the helper (TBase's helper is reached before TBase's member). Checking
       only the exact class would lose g; checking members first would lose b

  Oracled against FPC 3.2.2 -Mobjfpc: same output, row for row. }
program test_class_helper_for_a_class;

type
  TBox = class
    Value: Integer;
  end;
  TBoxHelper = class helper for TBox
    function Doubled: Integer;
    function Scaled(k: Integer): Integer;
    function Twice: Integer;
  end;

  TBase = class
    function Name: string; virtual;
  end;
  TDerived = class(TBase)
    function Name: string; override;
  end;
  TBaseHelper = class helper for TBase
    function Name: string;
    function Shout: string;
  end;

  TOther = class(TBase)
  end;

  TThing = class
    function Tag: string;
  end;
  TThingHelper = class helper for TThing
    function Tag2: string;
  end;

function TBoxHelper.Doubled: Integer;
begin
  Doubled := Value * 2;
end;

function TBoxHelper.Scaled(k: Integer): Integer;
begin
  Scaled := Self.Value * k;
end;

function TBoxHelper.Twice: Integer;
begin
  Twice := Self.Doubled;
end;

function TBase.Name: string;
begin
  Name := 'base';
end;

function TDerived.Name: string;
begin
  Name := 'derived';
end;

function TBaseHelper.Name: string;
begin
  Name := 'helper';
end;

function TBaseHelper.Shout: string;
begin
  Shout := 'shout:' + Name;
end;

function TThing.Tag: string;
begin
  Tag := 'T';
end;

function TThingHelper.Tag2: string;
begin
  Tag2 := Tag + '2';
end;

var
  b: TBox;
  o: TBase;
  d: TDerived;
  x: TOther;
  t: TThing;
begin
  b := TBox.Create;
  b.Value := 21;
  WriteLn('a ', b.Doubled);
  WriteLn('e ', b.Scaled(3));
  WriteLn('d ', b.Twice);

  o := TBase.Create;
  WriteLn('b ', o.Name);
  WriteLn('f ', TBase(o).Name);

  d := TDerived.Create;
  WriteLn('f2 ', TBase(d).Name);
  WriteLn('h  ', d.Name);

  x := TOther.Create;
  WriteLn('g  ', x.Shout);

  t := TThing.Create;
  WriteLn('c ', t.Tag2);

  b.Free;
  o.Free;
  d.Free;
  x.Free;
  t.Free;
end.
