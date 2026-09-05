{ Low/High of a set whose ELEMENT is a subrange, through both spellings.

  `type TCS = set of 'c'..'k'` lost its element bounds where the inline
  `var b: set of 'c'..'k'` kept them: ParseSetElemSpec captured bounds only in
  its tkInteger arm, so a subrange spelled any other way took the
  ParseTypeKind branch and registered Hi < Lo -- "not a subrange" -- and
  Low/High fell back to the element TYPE's full range, 0 and 255. Two paths for
  one concept and the second stayed broken.

  BOTH SPELLINGS ARE ASSERTED, and the inline rows are the control: they were
  right before the fix, so a run where only the alias rows are checked cannot
  tell a fix from a coincidence. The integer rows are a second control -- they
  went through the arm that always worked.

  DELIBERATELY NOT ASSERTED: `Write` of an inline char set's Low/High, which
  still prints 99 and 107 where fpc prints c and k. That is the element KIND
  rather than its bounds, and it belongs to
  decide-how-a-type-carries-an-identity-its-kind-cannot-hold. The ALIAS spelling
  does print c and k and is asserted below, which is why the two are separable.

  Verified against fpc 3.2.2.
  bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind }
program test_set_elem_bounds;
type
  TDay     = (sat, sun, mon, tue);
  TCharSet = set of 'c'..'k';
  TIntSet  = set of 1..10;
  TEnumSet = set of TDay;
  TEnumSub = set of sun..mon;
var
  ci: set of 'c'..'k'; ca: TCharSet;
  ii: set of 1..10;    ia: TIntSet;
  ea: TEnumSet;        es: TEnumSub;
begin
  WriteLn('char inline ', Ord(Low(ci)), ' ', Ord(High(ci)));
  WriteLn('char alias  ', Ord(Low(ca)), ' ', Ord(High(ca)));
  WriteLn('int  inline ', Ord(Low(ii)), ' ', Ord(High(ii)));
  WriteLn('int  alias  ', Ord(Low(ia)), ' ', Ord(High(ia)));
  WriteLn('enum whole  ', Ord(Low(ea)), ' ', Ord(High(ea)));
  WriteLn('enum sub    ', Ord(Low(es)), ' ', Ord(High(es)));
  WriteLn('alias chars ', Low(ca), High(ca));
end.
