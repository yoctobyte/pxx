program test_nested_alias_visible_through_enclosing_chain;
{$mode delphi}
{ A type nested in a class must be visible to declarations further nested
  inside it -- the ordinary lexical inner-scope rule.

  It broke because alias visibility was a LIST OF RANGES rather than a rule.
  Parsing a nested type's body retargets ParsingClassBodyCi at that nested
  type, so for exactly the span of a nested record's field list the enclosing
  class stopped being the value the predicate compared against, and a sibling
  nested type declared two lines above became `unknown type`. A nested POINTER
  kept working, which is why it read as fixed.

  DEPTH 2 IS THE POINT OF THIS FILE. A fifth arm comparing against "the
  enclosing class" would pass row 1 and fail row 3; only walking the chain
  answers both. So the deep row is not extra coverage, it is the row that
  distinguishes the rule from one more special case.

  Regression window: green on pin fe1e9c37d322, broken by c01eb17a8, still
  broken at 5daad03f5. Bisected over 63 commits, each step seeded from the pin.
  bug-p-a-nested-record-field-cannot-see-a-sibling-nested-type }

type
  TFac = class
  public type
    { row 1 -- a sibling nested type used by a nested RECORD FIELD }
    TFacClass = class of TFac;
    TVMT = record __ClassRef: TFacClass; end;

    { row 2 -- a plain alias, to show it is not about class-of }
    TCount = Integer;
    TBox = record n: TCount; end;

    { row 3 -- DEPTH 2: a record nested inside a record nested inside the
      class, whose field names a type owned by the outermost of the three }
    TInner = record
      deep: record
        ref: TFacClass;
        m: TCount;
      end;
    end;

    { row 4 -- the pointer spelling, which never broke; kept so a regression
      that fixes fields by breaking pointers cannot pass }
    PFacClass = ^TFacClass;
  end;

  { row 5 -- unit-level control: same shape, no nesting }
  TPlain = class end;
  TPlainClass = class of TPlain;
  TPlainVMT = record r: TPlainClass; end;

var
  vmt: TFac.TVMT;
  box: TFac.TBox;
  inner: TFac.TInner;
  pc: TFac.PFacClass;
  cr: TFac.TFacClass;
  plain: TPlainVMT;
  bad: Integer;
begin
  bad := 0;

  vmt.__ClassRef := TFac;
  if vmt.__ClassRef = nil then begin writeln('row1 nil'); bad := bad + 1; end;

  box.n := 7;
  if box.n <> 7 then begin writeln('row2 ', box.n); bad := bad + 1; end;

  inner.deep.ref := TFac;
  inner.deep.m := 9;
  if inner.deep.ref = nil then begin writeln('row3 ref nil'); bad := bad + 1; end;
  if inner.deep.m <> 9 then begin writeln('row3 m ', inner.deep.m); bad := bad + 1; end;

  cr := TFac;
  pc := @cr;
  if pc^ = nil then begin writeln('row4 nil'); bad := bad + 1; end;

  plain.r := TPlain;
  if plain.r = nil then begin writeln('row5 nil'); bad := bad + 1; end;

  if bad = 0 then writeln('NESTEDCHAIN OK') else writeln('NESTEDCHAIN FAILED ', bad);
end.
