program BinopOperandOrder;
{ feature-opt-o3-operand-order-for-non-commutative-binops (W1 slice 9).

  When BOTH subtrees of a binop are proven pure, the RIGHT one is evaluated
  first and parked in the scratch register, so the left value is produced last
  and is already in rax. That drops the restore move: three moves become two.

  The dangerous version of this pass is the one that checks only the RIGHT
  subtree -- which is what the arm below it already does, legitimately, because
  it evaluates left FIRST. Reversing the order needs BOTH sides pure: a left
  with side effects must not be moved after a right that can read them.

  So the control rows here are the impure ones, and they are built to the band
  rule: `Bump` returns a value straddling a `shr` boundary, so a wrongly-early
  right read differs from the correct one by exactly 1. Picking a round number
  hides it -- 100 shr 1 and 101 shr 1 are both 50, and that version of this test
  passed while the reorder was firing illegally. Values verified against FPC. }

var
  gLog: string;
  gV: LongInt;

function Bump(tag: Char; v: LongInt): LongInt;
begin
  gLog := gLog + tag;
  gV := gV + v;
  Bump := gV;
end;

function PureBoth(a, b, c: LongInt): LongInt;
begin
  { both subtrees pure and complex -> the new arm fires. `-` is non-commutative,
    so a true operand SWAP (as opposed to an evaluation reorder) flips the sign }
  PureBoth := (a + b) - (c shr 1);
end;

function LeftImpure: LongInt;
begin
  { left has a side effect the right subtree READS. Correct order: Bump runs
    first, gV becomes 102, 102 shr 1 = 51, result 102 - 51 = 51.
    Wrongly reordered: 101 shr 1 = 50 read first, result 102 - 50 = 52. }
  gV := 101;
  LeftImpure := Bump('L', 1) - (gV shr 1);
end;

function BothImpure: LongInt;
begin
  gV := 0;
  BothImpure := Bump('a', 10) - Bump('b', 3);
end;

var r: LongInt;
begin
  WriteLn('pure=', PureBoth(1000, 7, 101));
  gLog := '';
  r := LeftImpure;
  WriteLn('leftimp=', r, ' log=', gLog);
  gLog := '';
  r := BothImpure;
  WriteLn('bothimp=', r, ' log=', gLog);
  WriteLn('done');
end.
