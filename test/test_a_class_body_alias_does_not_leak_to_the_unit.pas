{ The UClass ALIAS table had no owning-class column, so `type TName = TOther;`
  written inside a class body was registered UNIT-GLOBALLY and beat another
  class's own nested type of the same name. Its sibling table Alias* has carried
  AliasOwnerCi for a long time; this one carried nothing, and the two tables
  agreed with each other perfectly because the copy was ABSENT rather than wrong.

  The generic rows are how it was found, and they are the expensive shape: the
  SECOND instantiation of a generic whose class body declares
  `TEnumSpec = specialize TEnum<T>` collapses that declaration to an alias of the
  FIRST one's hoisted class, the alias goes in unit-globally, and `TOther.TEnumSpec`
  then resolves through it. Silent wrong value, then a crash -- `s` printed a raw
  address and reading the other order segfaulted. Both declaration orders are
  asserted BECAUSE the defect was "last one registered wins": one order alone
  passes with the bug still in.

  The leak row is the direct control and needs no generics at all: the class body
  is declared BEFORE the unit-level alias of the same name, so the buggy
  first-match-in-this-unit lookup returns the class's row.

  Expected values are the fpc 3.2.2 oracle.
  bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization }
program test_a_class_body_alias_does_not_leak_to_the_unit;

{$mode objfpc}

uses uclsalias;

type
  TS = specialize TList7<String>;
  TI = specialize TList7<Integer>;

  { the class body declares TName first... }
  THolder = class(TObject)
  type TName = TBlue;
  public
    function Mine: TName;
  end;

{ ...and the unit level declares its own afterwards }
type TName = TRed;

function THolder.Mine: TName;
begin
  Result := TName.Create;
  Result.B := 'inner';
end;

var
  a: TI; b: TS;
  ei: TI.TEnumSpec; es: TS.TEnumSpec;
  h: THolder; outer: TName;
begin
  a := TI.Create; b := TS.Create;

  { the order the defect got WRONG: the later-declared TI won for both }
  es := b.Mk('hi');
  WriteLn('s ', es.GetCurrent);
  ei := a.Mk(9);
  WriteLn('i ', ei.GetCurrent);

  { and the same pair read the other way round }
  WriteLn('pair ', a.Mk(4).GetCurrent, ' ', b.Mk('zz').GetCurrent);

  { the class body's TName is TBlue; the unit's own TName is TRed }
  h := THolder.Create;
  WriteLn('inner ', h.Mine.B);
  outer := TName.Create;
  outer.R := 77;
  WriteLn('outer ', outer.R);
end.
