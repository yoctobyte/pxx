program test_a_class_var_of_class_type_carries_its_record_identity_through_a_chain;
{ bug-p-a-chained-class-var-of-class-type-loses-its-record-identity

  Both receiver arms resolved a class var through an instance and then threw
  the class var's RECORD IDENTITY away -- `recName := REC_NONE` -- while the
  selector loop CONTINUED. Whatever came next therefore had no namespace to be
  looked up in.

  IT BREAKS ONLY WHEN BOTH LINKS ARE PER-CLASS, and that is why it survived.
  A field read further down the loop re-derives the record from the node, so
  `c.Inner.AnInstanceField` was right; the class-var arm asks
  `FindClassVar(recName - REC_UCLASS_BASE, ...)` DIRECTLY, so with REC_NONE in
  hand a class var or class const selected off another class var fell past
  every arm to the no-namespace fallback and became a read at offset 0.
  MEASURED before the fix: `c.Inner.IV` printed 4265192 where fpc prints 22 --
  the SAME constant for every member tried, which is the tell that no member
  was being read at all -- while `TC.Inner.IV` on the very same object was
  right. A silent wrong value, no diagnostic, and two correct neighbours on
  either side of it.

  `class var` OPENS A SECTION, and this file spells every member's kind out
  because that rule cost a probe. In

      TInner = class
        class var IV: LongInt;
        F: LongInt;
      end;

  F is a CLASS var too -- measured under both compilers, `a.F := 1; b.F := 2`
  leaves both reading 2. A fixture that means to contrast a class var with an
  instance field and does not re-open a `var` section is contrasting a class
  var with a class var, and every row still passes.

  Rows 1 and 10 are the controls: the QUALIFIED spelling was correct
  throughout, so a fix that broke it would look exactly like a fix that worked.
  Every row is byte-identical to fpc 3.2.2. }

type
  TPt = record
    X, Y: LongInt;
  end;

  TInner = class
    class var IV: LongInt;
  var
    F: LongInt;
    function Twice: LongInt;
  end;

  TMid = class
    class var Leaf: TInner;
  end;

  TC = class
    class var Inner: TInner;
    class var Mid: TMid;
    class var P: TPt;
    const CP: TPt = (X: 8; Y: 9);
  end;

function TInner.Twice: LongInt; begin Twice := F * 2; end;

var
  fails: Integer;
  c: TC;

procedure Check(const what: AnsiString; got, want: LongInt);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  TC.Inner := TInner.Create;
  TC.Mid := TMid.Create;
  TMid.Leaf := TInner.Create;
  TInner.IV := 22;
  TC.Inner.F := 7;
  TMid.Leaf.F := 5;
  TC.P.X := 3; TC.P.Y := 4;
  c := TC.Create;

  { 1: THE CONTROL. The qualified receiver was right before the fix. }
  Check('1: qualified, chained to a class var', TC.Inner.IV, 22);

  { 2: THE ROW THIS FILE EXISTS FOR -- both links per-class. }
  Check('2: instance receiver, chained to a class var', c.Inner.IV, 22);

  { 3: the neighbour that already worked, kept because it is the boundary:
    an INSTANCE field off the same chain re-derives the record further down,
    which is exactly what made row 2 invisible. }
  Check('3: instance receiver, chained to an instance field', c.Inner.F, 7);

  { 4: a METHOD off the chain -- a third kind of selector, and it needs the
    record identity to find the method at all. }
  Check('4: a method off the chain', c.Inner.Twice, 14);

  { 5: the LVALUE side. The chain is a store target too, and a store to
    offset 0 would corrupt rather than merely misread. }
  c.Inner.F := 50;
  Check('5: assignment through the chain', TC.Inner.F, 50);

  { 6: a class var of RECORD type, not class type -- the other half of the
    `(tk = tyClass) or (tk = tyRecord)` guard. }
  Check('6a: a record class var through an instance', c.P.X, 3);
  Check('6b: ...both fields', c.P.Y, 4);

  { 7: TWO class-var links deep. The loop runs once per selector, so a
    two-link chain is a different assertion from a one-link one. }
  Check('7: class var -> class var -> instance field', c.Mid.Leaf.F, 5);

  { 8: the OTHER receiver arm. A parenthesised receiver leaves ParseLValueAST
    and arrives in ParseClassRecordSelectors, which had the same clearing --
    the sibling arm of a double case, fixed together. }
  Check('8: a parenthesised receiver, chained', (c).Inner.IV, 22);

  { 9: a TYPED class CONST of record type. It enters as a SYMBOL rather than a
    literal node, which is the fourth site with the same clearing. }
  Check('9a: a record class const through an instance', c.CP.X, 8);
  Check('9b: ...both fields', c.CP.Y, 9);

  { 10: the other control -- the qualified spelling of the record class var. }
  Check('10: qualified record class var', TC.P.X, 3);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CLASSVARCHAIN OK');
end.
