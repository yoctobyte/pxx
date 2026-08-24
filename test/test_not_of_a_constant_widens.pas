program test_not_of_a_constant_widens;
{ `not` over a CONSTANT ordinal is evaluated in a signed 64-bit type, and `not`
  over a VARIABLE complements at the variable's own width. Both halves matter and
  they disagree on purpose: `not High(Byte)` is -256 while `not b` on a `b: Byte`
  holding 255 is 0.

  pxx complemented a constant inside its small type, so `not High(Byte)` came out
  0, `not Low(Byte)` 255 and `not Ord('A')` 190 -- positive numbers where fpc
  gives negative ones, silently, in any expression that masks with a named or
  builtin constant. The rule was already implemented for unary MINUS
  (ASTConstIntValue exists to type a negated constant); `not` had never been
  given it.

  Every row below is fpc 3.2.2's own answer on the same source, and the whole
  `not` surface around it -- 47 operand shapes, variables, casts, comparisons,
  boolean ops, builtins -- was swept against fpc when this landed.
  bug-p-not-of-a-builtin-round-or-trunc-call-is-logical }
var
  b: Byte; si: ShortInt; w: Word; sm: SmallInt; c: Cardinal;
  i: Integer; i64: Int64; ch: Char; d: Double; s: AnsiString;
const
  KC = 200;
begin
  b := 1; si := 1; w := 1; sm := 1; c := 1; i := 1; i64 := 1;
  ch := 'A'; d := 1.5; s := 'abc';
  { the VARIABLE half: each complements at its own width }
  WriteLn('var byte    : ', not b);
  WriteLn('var shortint: ', not si);
  WriteLn('var word    : ', not w);
  WriteLn('var smallint: ', not sm);
  WriteLn('var cardinal: ', not c);
  WriteLn('var integer : ', not i);
  WriteLn('var int64   : ', not i64);
  WriteLn('ord var char: ', not Ord(ch));
  { ...and the CONSTANT half: all of these widen to signed 64-bit }
  WriteLn('const 255   : ', not 255);
  WriteLn('const 0     : ', not 0);
  WriteLn('named const : ', not KC);
  WriteLn('const expr  : ', not (KC + 1));
  WriteLn('ord lit char: ', not Ord('A'));
  WriteLn('high byte   : ', not High(Byte));
  WriteLn('low byte    : ', not Low(Byte));
  WriteLn('high word   : ', not High(Word));
  { ...and the one whose complement does NOT fit in 32 bits, so the node really
    is Int64 over a 32-bit-tagged operand. arm32's IR_NOT emitted the operand
    without widening it and left the high word holding whatever was in r1:
    -578716232904081408 instead of -4294967296, on that target alone. }
  WriteLn('high card   : ', not High(Cardinal));
  WriteLn('sizeof int  : ', not SizeOf(i));
  { the builtin ordinal calls the ticket named, on values rather than constants }
  WriteLn('round       : ', not Round(d));
  WriteLn('trunc       : ', not Trunc(d));
  WriteLn('length      : ', not Length(s));
  WriteLn('abs         : ', not Abs(-3));
  WriteLn('pos         : ', not Pos('b', s));
end.
