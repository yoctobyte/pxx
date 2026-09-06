program test_a_bracket_at_the_head_of_an_argument_is_an_operators_left_operand;

{$mode objfpc}
{$modeswitch arrayoperators}
{$modeswitch advancedrecords}

{ `f([0] + a)` -- a `[` at the HEAD of an argument, with an operator after the
  closing `]`.

  THE ARGUMENT DOOR CONSUMED THE WHOLE BRACKET, so a leading `[...]` could never
  be an operator's LEFT operand. Reported by frankS with the two rows that make
  it a door problem rather than a concatenation problem, and they are the reason
  this file is short:

      f(a + [4])      bracket NOT at the head              -> compiled, correct
      t := [0] + a    same expression, statement position  -> compiled, correct
      f([0] + a)      bracket AT the head                  -> `expected comma or
                                                              close parenthesis`

  Concatenation was fine and both operands were fine. So the fix is a REFUSAL to
  take the door -- TryParseBracketArgForSlot now answers "not mine" when the
  matching `]` is followed by anything but `,` or `)`, and the ordinary
  expression parser, which already parses this shape (that is what the statement
  row proves), gets it.

  ONE DOOR, NINE CALLERS, AND THAT IS WHY THE SHAPES ARE HERE. The bracket door
  was unified across every Pascal call path on 2026-09-06; this is the first
  change to its decision since, so each caller is asked once. A single-shape
  fixture would be green on eight of the nine no matter what the ninth did --
  measured, not assumed: when the parenless-default bug was filed, ten of its
  eleven receiver shapes were already correct.

  EVERY ROW PRINTS CONTENTS, NOT LENGTH. `Length` is the same number for a
  correct concatenation, a reversed one and a vector of empty elements, so a
  length assertion passes on garbage; the values are distinct and ascending so a
  mis-ordering cannot look like a match.

  THE CONTROL IS `a + [4]` ON THE SAME CALLEE IN THE SAME PROGRAM -- the shape
  that always worked. If the fix had broken the door instead of narrowing it,
  the control fails and the head row passes, which is a different picture from
  both failing.

  fpc 3.2.2 needs the arrayoperators modeswitch for `+` on dynamic arrays at
  all (it is on by default in mode delphi only); without it fpc types a bare
  `[0]` in an argument as `Set Of Byte` and refuses BOTH orders, so the oracle
  would be answering about the modeswitch and not about the door.
  bug-p-a-bracket-at-the-head-of-an-argument-cannot-be-an-operators-left-operand }

type
  TArr = array of LongInt;

  TCls = class
    function M(const r: array of LongInt): AnsiString;
    procedure Bump(var r: array of LongInt);
    class function CM(const r: array of LongInt): AnsiString;
    constructor Create(const r: array of LongInt);
  end;

  TRec = record
    function RM(const r: array of LongInt): AnsiString;
  end;

  IFace = interface
    ['{1FD4C0A2-0D3E-4E77-9A6B-2C1B5E8A0011}']
    function IM(const r: array of LongInt): AnsiString;
  end;

  TImpl = class(TInterfacedObject, IFace)
    function IM(const r: array of LongInt): AnsiString;
  end;

  TCb = function(const r: array of LongInt): AnsiString;

var
  fails: LongInt = 0;
  ctorSaw: AnsiString = '';

function Show(const r: array of LongInt): AnsiString;
var i: LongInt; s, d: AnsiString;
begin
  s := '[';
  for i := 0 to High(r) do
  begin
    if i > 0 then s := s + ',';
    Str(r[i], d);
    s := s + d;
  end;
  Str(Length(r), d);
  Show := s + '] n=' + d;
end;

function TCls.M(const r: array of LongInt): AnsiString;    begin M := Show(r); end;
procedure TCls.Bump(var r: array of LongInt);
var i: LongInt;
begin
  for i := 0 to High(r) do r[i] := r[i] + 100;
end;
class function TCls.CM(const r: array of LongInt): AnsiString; begin CM := Show(r); end;
constructor TCls.Create(const r: array of LongInt);        begin ctorSaw := Show(r); end;
function TRec.RM(const r: array of LongInt): AnsiString;   begin RM := Show(r); end;
function TImpl.IM(const r: array of LongInt): AnsiString;  begin IM := Show(r); end;

procedure Expect(const what, got, want: AnsiString);
begin
  if got = want then
    WriteLn('ok   ', what, ' ', got)
  else
  begin
    WriteLn('FAIL ', what, ' got ', got, ' want ', want);
    Inc(fails);
  end;
end;

var
  a: TArr;
  o: TCls;
  r: TRec;
  i: IFace;
  cb: TCb;
  made: TCls;
const
  HEAD = '[0,1,2,3] n=4';   { [0] + a }
  TAIL = '[1,2,3,4] n=4';   { a + [4] }
begin
  a := [1, 2, 3];
  o := TCls.Create([9]);    { the ctor's own slot, plain -- door still taken }
  r.RM([9]);
  i := TImpl.Create;
  cb := @Show;

  { --- the control: the shape that always worked, at every door --- }
  Expect('ctrl free   ', Show(a + [4]), TAIL);
  Expect('ctrl method ', o.M(a + [4]), TAIL);
  Expect('ctrl class  ', TCls.CM(a + [4]), TAIL);
  Expect('ctrl record ', r.RM(a + [4]), TAIL);
  Expect('ctrl iface  ', i.IM(a + [4]), TAIL);
  Expect('ctrl procvar', cb(a + [4]), TAIL);

  { --- the bug: the SAME expression with the operands swapped --- }
  Expect('head free   ', Show([0] + a), HEAD);
  Expect('head method ', o.M([0] + a), HEAD);
  Expect('head class  ', TCls.CM([0] + a), HEAD);
  Expect('head record ', r.RM([0] + a), HEAD);
  Expect('head iface  ', i.IM([0] + a), HEAD);
  Expect('head procvar', cb([0] + a), HEAD);

  { the constructor door -- it takes the bracket by a different route
    (ClassCtorArraySigAt), so it is asked separately }
  made := TCls.Create([0] + a);
  Expect('head ctor   ', ctorSaw, HEAD);

  { THE SCAN MUST FIND THE MATCHING `]`, NOT THE FIRST ONE. A subscript inside
    the head list closes a bracket that is not ours; stopping there would read
    the `,` after it as the end of the argument and take the door anyway. }
  Expect('head subscr ', Show([a[0] * 10, 9] + a), '[10,9,1,2,3] n=5');

  { and an operator on BOTH sides of the head bracket's operand }
  Expect('head chained', Show([0] + (a + [4])), '[0,1,2,3,4] n=5');

  { the door must still be taken when the bracket IS the whole argument --
    a plain `[...]` argument at each of the two arms the door decides between }
  Expect('plain scalar', Show([5, 6, 7]), '[5,6,7] n=3');
  Expect('plain method', o.M([5, 6, 7]), '[5,6,7] n=3');

  { --- THE CONTROLS FOR THE SECOND FIX, which must not have widened --- }

  { a bare variable at a const open-array door still takes the LVALUE path }
  Expect('bare var    ', o.M(a), '[1,2,3] n=3');

  { A `var` open array is a GENUINE var-binding target and must still bind by
    reference: ParamBindsAnExpression is false for it, so the bare-lvalue parse
    is forced and the callee's writes reach the caller. This is the row that
    fails if the widening went one predicate too far -- an expression bound to a
    `var` parameter writes into a temporary and the caller sees nothing. }
  o.Bump(a);
  Expect('var writes  ', Show(a), '[101,102,103] n=3');
  a := [1, 2, 3];

  if fails = 0 then WriteLn('HEADBRACKET OK') else WriteLn('HEADBRACKET FAILED ', fails);
end.
