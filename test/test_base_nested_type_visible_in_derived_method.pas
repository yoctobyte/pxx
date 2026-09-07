program test_base_nested_type_visible_in_derived_method;
{$mode delphi}
{ A type nested in a BASE class, named from inside a DERIVED class's METHOD
  IMPLEMENTATION. `AliasVisibleHere` arm 3 compared the alias's owner to
  MethImplOwnerCi EXACTLY, so only the class that literally declared the type
  could name it and every descendant got `unknown type`.

  Two chains, and they are not the same question. AliasOwnsThrough walks
  UClsEnclosingCi -- where a type is DECLARED -- and is tested by
  test_nested_alias_visible_through_enclosing_chain. This file is the OTHER
  one, UClsParent: what a class DESCENDS from. A type can be reachable by one
  and not the other, so one walk cannot answer both and neither test replaces
  the other.

  NOT ABOUT METHOD POINTERS, which is why row B is here: `TAmt = Integer` is
  refused by pin v407 exactly as the procedural `TSel` is. A test carrying only
  the procedural row would read as a method-pointer bug and invite a fix in the
  wrong place.

  Row C is TWO levels up, so the walk is distinguishable from a single
  parent check -- the same reason the lexical test carries a depth-2 row.

  rtl-generics spells row A, and it is corpus rung 6a's wall at
  generics.defaults:2279 (`unknown type: TSelectMethod`, owned by
  TComparerService, named from THashService<T>.LookupEqualityComparer).

  Scope, measured and deliberately NOT widened here: the derived class BODY and
  the qualified `TDer.TSel` spellings resolve the type by other paths, and two
  further spellings -- a FIELD of the base's nested type, and CALLING through
  the qualified name -- still fail for a different reason and are filed
  separately. Asserting them here would make this green depend on an unrelated
  fix. }
type
  TBase = class
  public type
    TSel = function(a: Integer): Integer of object;
    TAmt = Integer;
  end;

  TDer = class(TBase)
    function Twice(a: Integer): Integer;
    function LocalSel: Integer;
    function LocalOrd: Integer;
  end;

  TGrand = class(TDer)
    function GrandOrd: Integer;
  end;

function TDer.Twice(a: Integer): Integer;
begin Twice := a * 2; end;

function TDer.LocalSel: Integer;
var s: TSel;                  { A: base's nested PROCEDURAL type }
begin s := Twice; LocalSel := s(21); end;

function TDer.LocalOrd: Integer;
var n: TAmt;                  { B: base's nested ORDINAL type }
begin n := 7; LocalOrd := n * 3; end;

function TGrand.GrandOrd: Integer;
var n: TAmt;                  { C: base-of-base, two parent hops }
begin n := 5; GrandOrd := n * 4; end;

var
  d: TDer;
  g: TGrand;
  ok: Boolean;
begin
  ok := True;
  d := TDer.Create;
  g := TGrand.Create;
  if d.LocalSel <> 42 then begin WriteLn('A=', d.LocalSel); ok := False; end;
  if d.LocalOrd <> 21 then begin WriteLn('B=', d.LocalOrd); ok := False; end;
  if g.GrandOrd <> 20 then begin WriteLn('C=', g.GrandOrd); ok := False; end;
  if ok then WriteLn('BASENESTED OK') else WriteLn('BASENESTED FAIL');
end.
