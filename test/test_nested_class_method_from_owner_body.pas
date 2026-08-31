program test_nested_class_method_from_owner_body;
{ A class's own body is TWO ranges of source — the declaration and the
  out-of-line implementations — and a bare nested-type name has to mean the
  same thing in both. Every value here is FPC 3.2.2's on this same source.

  `TInner` is declared FIRST at unit level as a decoy, so the nested ones lose
  the race for the bare name. Two things were then wrong, and they are one bug:

  * A bare nested-type name inside a METHOD BODY fell through to the flat unit
    table, because ParsingClassBodyCi is set only while a class DECLARATION is
    being parsed. `TPlain.Probe` called the DECOY's GetIt and printed 1 where
    FPC prints 7 — a wrong method, silently, with no generic anywhere in sight.
    MethImplOwnerCi is the missing half of that scope.

  * The declaration named its proc after the type AS WRITTEN and the
    out-of-line implementation named it after the class ROW, which
    AddClassLikeType qualifies whenever the bare name is taken. Two spellings,
    two procs: the declaration's had the callers and no body. In a generic that
    is unmissable, because a specialization re-materialises the nested type
    against the template's own row every time — `unresolved forward:
    TInner.GetIt` at link time. Both sides now read the row.

  bug-p-a-nested-class-method-called-from-inside-its-generic-outer-is-unresolved }
{$mode objfpc}

type
  TInner = class
    Z: Integer;
    function GetIt: Integer;
  end;

  TPlain = class
  public type
    TInner = class
      F: Integer;
      function GetIt: Integer;
    end;
    function Probe: Integer;
  end;

  generic TOuter<T> = class
  public type
    TInner = class
      F: Integer;
      function GetIt: Integer;
    end;
    function Make: TInner;
    function Probe: Integer;
  end;

  TO2 = specialize TOuter<Integer>;
  TO3 = specialize TOuter<LongInt>;

function TInner.GetIt: Integer;
begin Result := 1; end;

function TPlain.TInner.GetIt: Integer;
begin Result := 7; end;

function TPlain.Probe: Integer;
var x: TInner;
begin x := TInner.Create; Result := x.GetIt; end;

function TOuter.TInner.GetIt: Integer;
begin Result := 9; end;

function TOuter.Make: TInner;
begin Result := TInner.Create; end;

function TOuter.Probe: Integer;
begin Result := Make.GetIt; end;

var
  a: TO2; b: TO3; p: TPlain; d: TInner;
begin
  a := TO2.Create; b := TO3.Create; p := TPlain.Create; d := TInner.Create;
  writeln('decoy          ', d.GetIt);
  writeln('plain          ', p.Probe);
  writeln('generic first  ', a.Probe);
  writeln('generic second ', b.Probe);
  writeln('from outside   ', a.Make.GetIt);
end.
