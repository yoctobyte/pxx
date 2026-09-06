program test_a_class_const_is_reachable_through_an_instance_receiver;
{ bug-p-a-class-const-is-unreachable-through-an-instance-receiver

  `TC.K` compiled and `c.K` answered `"K": no such member on this record/class`
  for the same const, because Pascal member dispatch is written more than once
  and only the TYPE-NAME receiver ever learned about class consts. Two of the
  three copies -- ParseLValueAST's field arm and ParseClassRecordSelectors --
  carry a FindClassVar arm and neither carried FindClassConst; a const declared
  in a class or a record body was therefore reachable by exactly one spelling.

  THE FIX IS ONE FUNCTION, NOT A THIRD COPY. ClassConstThroughReceiver (in
  pasparser_class.inc, which precedes pasparser_lval.inc in the include order)
  holds the whole resolution -- lookup, visibility, mangle, literal-or-symbol --
  and both receiver arms call it. Growing a second copy is the shape
  normalise-dont-special-case exists to refuse: the second copy is the one that
  stays broken.

  THE ROWS ARE THE POSITIVE CONTROL AND THEY WERE MEASURED, not assumed. With
  the fix reverted and the compiler rebuilt, this file does not compile: ten
  rows are refused with `no such member`, at lines carrying rows 2..9, 11 and
  12. Rows 1 and 10 -- the QUALIFIED spellings -- compile in both trees, which
  is what makes them controls rather than filler: they are the half of the
  double case that already worked, and a fix that broke them would look exactly
  like a fix that worked.

  THE THIRD COPY WAS ASKED AND ANSWERED NO. pasparser_expr.inc's computed-value
  arm (`(expr).Member` on a grouped or cast value) is a fourth member dispatch
  and it did NOT need the arm: measured, both `(d).DK` and `GD.DK` route through
  ParseClassRecordSelectors, so row 8 and row 9 are that measurement written
  down. A later reader who greps for member dispatch will find that copy and
  wonder; these two rows are the answer.

  Every row is byte-identical to fpc 3.2.2. The advancedrecords modeswitch
  below is what fpc needs before it will parse a const section in a RECORD
  body; pxx accepts the record either way, and the directive is written here
  so that the file fpc compiles and the file pxx compiles are the same source
  rather than two files that agree.

  NOT ASSERTED HERE: a class const chained through a `class var` of CLASS type
  (`c.Inner.F`) gives a garbage value under pxx. That is a SEPARATE and
  PRE-EXISTING defect -- measured against a tree with this fix reverted, which
  produced the same garbage -- and it has its own ticket. Asserting it here
  would make this file fail for a reason that is not its subject. }

{$modeswitch advancedrecords}

type
  TBase = class
    F: LongInt;
    const BK = 11;
    const BS = 'base';
  end;

  TDer = class(TBase)
    const DK = 22;
    const DF: Double = 1.5;
  end;

  TR = record
    G: LongInt;
    const RK = 33;
  end;

var
  fails: Integer;
  b: TBase;
  d: TDer;
  r: TR;

function GD: TDer;
begin
  GD := d;
end;

procedure Check(const what: AnsiString; got, want: LongInt);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

procedure CheckS(const what, got, want: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got "', got, '" want "', want, '"');
    fails := fails + 1;
  end;
end;

{ The receiver's STATIC type is what resolves the const, and a parameter is the
  cheapest way to say that: `x` is declared TBase and holds a TDer, and BK must
  come from TBase. }
procedure ThroughAParameter(x: TBase);
begin
  Check('7: through a parameter of the ancestor type', x.BK, 11);
end;

begin
  fails := 0;
  b := TBase.Create;
  d := TDer.Create;

  { 1 and 10: THE CONTROLS. Both compiled before the fix and must still. }
  Check('1: the qualified spelling still resolves', TBase.BK, 11);
  Check('10: ...and the record one too', TR.RK, 33);

  { 2, 3: the const declared in the receiver's own class, integer and string. }
  Check('2: an instance receiver reaches the class const', b.BK, 11);
  CheckS('3: including a STRING const', b.BS, 'base');

  { 4, 5: inheritance. FindClassConst walks ancestors, and an instance of the
    DERIVED class must reach both the inherited const and its own. }
  Check('4: an inherited const through a derived instance', d.BK, 11);
  Check('5: and the derived class''s own', d.DK, 22);

  { 6: a TYPED const. This is the arm where the helper returns a SYMBOL rather
    than a literal node -- EmitClassConstNode declines and FindSym answers -- so
    it is a different half of the function from every other row here. }
  if (d.DF < 1.4999) or (d.DF > 1.5001) then
  begin
    WriteLn('FAIL 6: typed class const through an instance: got ', d.DF:0:4);
    fails := fails + 1;
  end;

  ThroughAParameter(d);

  { 8, 9: the two receiver SHAPES that are not a plain variable. See the third-
    copy note above: these are the measurement that says the computed-value arm
    in pasparser_expr.inc does not need its own copy. }
  Check('8: a computed receiver (a function result)', GD.DK, 22);
  Check('9: a parenthesised receiver', (d).DK, 22);

  { 11: a RECORD instance. The record member loop is a separate loop from the
    class one and this repo keeps finding that fixing one arm of a double case
    leaves the sibling broken; ParseClassRecordSelectors serves both. }
  r.G := 1;
  Check('11: a record instance receiver', r.RK, 33);

  { 12: inside an EXPRESSION, not as a bare WriteLn argument. A const that
    resolves only in argument position would still pass every row above. }
  d.F := 4;
  Check('12: in the middle of an expression', d.F + d.DK, 26);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CLASSCONSTRECV OK');
end.
