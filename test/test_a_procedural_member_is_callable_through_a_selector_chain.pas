{ Calling a procedural member reached through a SELECTOR CHAIN.

  `o.Items[0].Fn(1)` and `TR(o).R.Fn(1)` were refused while `o.Ev(1)`,
  `o.R.Fn(1)` and `o.GetI(0).Fn(1)` compiled. The ticket recorded the indexed
  property as the ingredient and that was wrong: a CAST base with no property
  in it fails identically, and an ordinary method call mid-chain succeeds. The
  ingredient is which walker parsed the chain — ParseClassRecordSelectors built
  no indirect call at any point, because its state is (node, tk, recId) and a
  SIGNATURE is a fourth fact it never carried, so a `(` ended the walk and was
  left in the stream.

  EVERY ROW PASSES A NEGATIVE ARGUMENT AND ASSERTS THE RETURNED VALUE, AND THAT
  IS THE WHOLE DESIGN OF THIS FILE. The refusals were the loud half. In
  assignment position the same chain COMPILED and discarded the argument list,
  assigning the truthiness of the method pointer — so it answered True for
  every argument, silently. A row asserting that these rows merely compile
  passes over that. A row asserting `Fn(5)` passes over it too, because True is
  both the correct answer and the failure value. Only an argument whose right
  answer is False separates them; `not Fn(-5)` does not, because it agrees with
  the bug by accident.

  Measured against fpc 3.2.2 -Mdelphi: every row below is fpc's own answer.
  Before the fix, binary e54f10adf969, rows E and F printed True where fpc
  printed False; after it, binary 3c59573e07f5, all rows agree.
  bug-p-a-call-through-an-indexed-property-in-the-chain-does-not-resolve }
program test_a_procedural_member_is_callable_through_a_selector_chain;
{$mode delphi}
type
  TFn = function(x: Integer): Boolean of object;
  TInner = record Fn: TFn; N: Integer; end;
  TOuter = record R: TInner; end;
  TR = class
  public
    FI: TInner;
    Ev: TFn;
    R: TInner;
    R2: TOuter;
    function GetI(i: LongInt): TInner;
    property Items[i: LongInt]: TInner read GetI; default;
    function Neg(x: Integer): Boolean;
    procedure Init;
  end;

var fails: Integer = 0;

procedure Chk(const what: string; got, want: Boolean);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

function TR.Neg(x: Integer): Boolean; begin Result := x > 0; end;
function TR.GetI(i: LongInt): TInner; begin Result := FI; end;
procedure TR.Init;
begin
  FI.Fn := Neg; FI.N := 7; Ev := Neg; R.Fn := Neg; R2.R.Fn := Neg;
end;

var
  o: TR;
  b: Boolean;
  v: TFn;
begin
  o := TR.Create;
  o.Init;

  { the shapes that already worked — they must keep working }
  Chk('A o.Ev(-5)',            o.Ev(-5),           False);
  Chk('B o.R.Fn(-5)',          o.R.Fn(-5),         False);
  Chk('C o.R2.R.Fn(-5)',       o.R2.R.Fn(-5),      False);
  Chk('D o.GetI(0).Fn(-5)',    o.GetI(0).Fn(-5),   False);

  { E and F are the defect: a property step and a CAST base. Both reach
    ParseClassRecordSelectors, which is the only thing they have in common —
    F contains no property at all. }
  Chk('E o.Items[0].Fn(-5)',   o.Items[0].Fn(-5),  False);
  Chk('F TR(o).R.Fn(-5)',      TR(o).R.Fn(-5),     False);

  { ...and the same two with a POSITIVE argument, so the file cannot be read as
    asserting "always False". These two passed under the bug. }
  Chk('G o.Items[0].Fn(5)',    o.Items[0].Fn(5),   True);
  Chk('H TR(o).R.Fn(5)',       TR(o).R.Fn(5),      True);

  { RESULT POSITION is an axis of its own: the three that REFUSED and the one
    that compiled-and-lied are the same chain in four positions. }
  b := o.Items[0].Fn(-5);
  Chk('I assignment RHS',      b,                  False);
  Chk('J condition',           o.Items[0].Fn(-5),  False);
  Chk('K argument position',   not (not o.Items[0].Fn(-5)), False);
  Chk('L operand of and',      o.Items[0].Fn(-5) and True,  False);

  { the value form still yields a callable procedural VALUE rather than a call }
  v := o.Items[0].Fn;
  Chk('M via a variable',      v(-5),              False);

  { arity is checked now, which is what discarding the argument list bypassed;
    the wrong-count spellings are refused at compile time, so what this row can
    assert is that the RIGHT count reaches the callee. }
  Chk('N argument reaches callee', o.Items[0].Fn(1), True);

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('CHAINCALL OK');
end.
