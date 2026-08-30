{ A BODILESS class nested inside a GENERIC template's own `type` section --
  `TIter = class(TBase<T>);` -- was counted as opening a body by the template
  capture's depth loop. It opens none, so the depth never came back down at this
  template's own `end`: the capture ran on and swallowed every following
  declaration until some later `end` balanced it.

  The damage is not a parse error at the swallowed text. The swallowed
  declarations' TYPE PARAMETERS are then in scope for THIS template's nested-
  specialization scan, so specializing it registers the swallowed class's
  prerequisites under the WRONG substitution set -- `TBox<TKey>` from TPair
  becomes a prerequisite of TList2<Integer>, whose only parameter is `T`, so
  `TKey` maps to nothing, survives as a literal, and is minted into the alias
  `TBox$TKey`. The error is `unknown type: TKey`, reported inside a specialized
  body far from anything the programmer wrote wrong.

  THE SAME DECISION, GOT RIGHT AT THE OUTER LEVEL AND WRONG AT THE NESTED ONE.
  `test_generic_bodiless_class_modifier` is the outer arm of exactly this bug --
  a bodyless template declaration -- and it was fixed in the up-front
  `bodyless` test. The depth loop that runs for templates that DO have a body
  kept its own hand-rolled copy of "is this `class` token an opener?", which knew
  about member prefixes (`class function`, `class var`) and not about bodiless
  declarations. Both now go through ClassTokOpensBody, which is the one place
  the question is answered.
  devdocs/dev/normalise-dont-special-case.md

  Corpus instance: rtl-generics' `TList<T>` declares
  `TEnumerator = class(TCustomListEnumerator<T>);` in its own `type` section.
  Measured with `--debug`, TList captured 10,914 tokens -- swallowing
  TCustomDictionary, 1,100 lines of unit -- against a corpus maximum of 1,677
  for every other template in the same file. After the fix it captures 515, and
  `unknown type: TKey` is gone from the corpus entirely.
  bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body

  The CONTROL is the first family below: the identical shape with a nested class
  that HAS a body. It compiled correctly before the fix and still does, which is
  what isolates bodilessness as the variable rather than nesting.

  Oracle: FPC prints the same line. }
program test_generic_bodiless_nested_class_in_type_section;

{$MODE DELPHI}

type
  TBox<T> = class
    V: T;
  end;

  TBase<T> = class
    F: T;
  end;

  { CONTROL -- nested class WITH a body: correct before the fix and after }
  TCtl<T> = class(TBase<T>)
  public
    type
      TInner = class(TBase<T>)
        Extra: T;
      end;
    function Get: T;
  end;

  { the declaration that follows the control, and must stay out of its capture }
  TCtlPair<CKey, CValue> = class
    B: TBox<CKey>;
    V: CValue;
  end;

  { SUBJECT -- nested class with NO body }
  TList2<T> = class(TBase<T>)
  public
    type
      TIter = class(TBase<T>);
    function Get: T;
  end;

  { swallowed by the overrun; its CKey/TKey then leaked into the scan above }
  TPair<TKey, TValue> = class
    B: TBox<TKey>;
    V: TValue;
  end;

function TCtl<T>.Get: T;
begin
  Result := F;
end;

function TList2<T>.Get: T;
begin
  Result := F;
end;

var
  c: TCtl<Integer>;
  cp: TCtlPair<Integer, string>;
  l: TList2<Integer>;
  p: TPair<Integer, string>;
begin
  c := TCtl<Integer>.Create;
  c.F := 3;
  cp := TCtlPair<Integer, string>.Create;
  cp.V := 'ctl';
  l := TList2<Integer>.Create;
  l.F := 7;
  p := TPair<Integer, string>.Create;
  p.V := 'sub';
  writeln('bodiless-nested ', c.Get, ' ', cp.V, ' ', l.Get, ' ', p.V);
end.
