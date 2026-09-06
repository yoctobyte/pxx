program test_a_sized_boolean_is_not_true_and_not_true_at_once;
{ `var a: ByteBool; a := True` made BOTH `if a` and `if not a` fire -- a
  compiling program took both branches, silently, no diagnostic -- because
  `not` on a sized boolean was an INTEGER complement. It was right for False
  only by accident (`not 0` is nonzero, which is the wanted answer), so the
  False rows below are the ones that CANNOT fail and the True rows are the
  whole assertion.

  The two families land nonzero for different arithmetic reasons and both are
  kept: `not` of a ByteBool 1 was 254 (unsigned byte) and of a LongBool 1 was
  -2 (signed 32-bit). Neither reading could have gone wrong the way the other
  did.
  bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time }
var bb, bb2, bb3: ByteBool; w: WordBool; l: LongBool; i: Integer;
begin
  bb := True;  Write('B+ '); if bb then Write('then '); if not bb then Write('NOT-THEN '); WriteLn;
  bb := False; Write('B- '); if bb then Write('then '); if not bb then Write('not-then '); WriteLn;
  w := True;   Write('W+ '); if w  then Write('then '); if not w  then Write('NOT-THEN '); WriteLn;
  w := False;  Write('W- '); if w  then Write('then '); if not w  then Write('not-then '); WriteLn;
  l := True;   Write('L+ '); if l  then Write('then '); if not l  then Write('NOT-THEN '); WriteLn;
  l := False;  Write('L- '); if l  then Write('then '); if not l  then Write('not-then '); WriteLn;

  { the `else` spelling of the same defect: a plain inversion rather than a
    double fire, which is the more recognisable shape }
  l := True;
  if not l then WriteLn('inverted') else WriteLn('correct');

  { A NONZERO value that is not 1 must still read as true and its `not` as
    false -- these types exist for C, where any nonzero is true and 1 is not
    privileged. This is the row a fix that merely canonicalised `True` to 1
    would fail. }
  i := 200; bb := ByteBool(i);
  Write('B200 '); if bb then Write('then '); if not bb then Write('NOT-THEN '); WriteLn;

  { SIGNEDNESS. FPC stores True all-bits-set and reads a sized boolean back
    through a SIGNED ordinal, so these are negative. A probe value must exceed
    the signed range to discriminate: ByteBool(200) separates the two worlds
    and WordBool(200) does NOT, because 200 fits a signed 16-bit and answers
    200 whether the kind is signed or not. }
  i := 200;   WriteLn('ord B200=',   Ord(ByteBool(i)));
  i := 255;   WriteLn('ord B255=',   Ord(ByteBool(i)));
  i := 40000; WriteLn('ord W40000=', Ord(WordBool(i)));
  i := 65535; WriteLn('ord W65535=', Ord(WordBool(i)));
  i := -1;    WriteLn('ord Lm1=',    Ord(LongBool(i)));

  { …and what `True` MATERIALISES as, which is a DIFFERENT question from the
    signedness above and needs its own rows. FPC stores all-bits-set, so
    Ord is -1 -- and LongBool was signed the whole time and still answered 1,
    which is the control that separates the two fixes. A row set built only on
    `True` reads as "the kind change did nothing"; one built only on 255 reads
    as "sized booleans are fixed". Both are wrong and both are one plausible
    test file away. }
  bb := True; w := True; l := True;
  WriteLn('ord bbT=', Ord(bb), ' wT=', Ord(w), ' lT=', Ord(l));
  bb := False; WriteLn('ord bbF=', Ord(bb));
  WriteLn('ord castT=', Ord(ByteBool(True)), ' ', Ord(WordBool(True)), ' ', Ord(LongBool(True)));
  { an INTEGER source is a reinterpret and keeps its bits -- the row that says
    materialising a truth value and casting a number are different questions }
  i := 200; WriteLn('ord cast200=', Ord(ByteBool(i)));

  { the widths are the reason these are not simply mapped onto Boolean, so
    assert them -- as a RELATION where one exists, so the row carries no
    per-target constant }
  WriteLn('sz=', SizeOf(ByteBool), ' ', SizeOf(WordBool), ' ', SizeOf(LongBool));

  { THE OPERATOR FAMILY, which is the same defect one operator over and is
    invisible to any probe using only 0 and 1. fpc 3.2.2 makes `and` and `or`
    on sized booleans LOGICAL and leaves `xor` BITWISE -- deliberate, since bit
    patterns are meaningful in the type family that exists for the C ABI -- so
    the asymmetry below is the assertion and not an accident. With
    a = ByteBool(200) and b = ByteBool(1) both true, `a and b` was 0 (bitwise
    200 and 1) and `a or b` was -55. }
  i := 200; bb := ByteBool(i); i := 1; bb2 := ByteBool(i); i := 0; bb3 := ByteBool(i);
  WriteLn('and=', bb and bb2, ' or=', bb or bb3);
  { the third xor row is the one that can FAIL: 200 xor 1 and 200 xor 0 are
    both nonzero and both TRUE, so a pair of them certifies nothing about the
    operator. `bb2 xor bb2` is 1 xor 1 = 0, the only FALSE the family can
    produce here. }
  WriteLn('xor tt=', bb xor bb2, ' xor tf=', bb xor bb3, ' xor same=', bb2 xor bb2);
  { …and comparing two truth values compares their TRUTH. `bb = bb2` for 200
    and 1 compared raw ordinals and said FALSE. }
  WriteLn('eq=', bb = bb2, ' ne=', bb <> bb2);

  { The TRUTH VALUE is what is asserted above, and the ORDINAL of a logical
    result deliberately is NOT. fpc 3.2.2's own answer for `Ord(x and y)` moves
    with the SHAPE of the operands -- 1 for two variables, -56 (the left
    operand's own bits) when the right side is written `ByteBool(1)` -- so
    there is no ordinal here to be compatible WITH. Per CLAUDE.md that is the
    intermediate, and the intermediate is latitude; the declared type's value
    is the claim. Do not add an Ord row to this block. }

  { CONTROL: plain Boolean, which was never wrong. Without it a `not` that had
    started answering False for everything would pass every row above. }
  WriteLn('ctl ', not True, ' ', not False);
end.
