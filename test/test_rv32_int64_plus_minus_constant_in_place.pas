{ riscv32: a 64-bit + or - of a constant that fits addi's 12 bits is done in
  place: the low word adds the immediate, sltiu with the same immediate is
  the carry (a negative immediate sign-extends to exactly its 32-bit addend),
  and the high word adds the carry and -1 for a negative constant. Carries
  and borrows across the word boundary in both directions, the immediate
  bounds -2048 and 2047, a 2048 just past them, zero, constants typed 32-bit
  signed and unsigned, folded named constants, and QWord operands. Output
  must match x86-64. }
program test_rv32_int64_plus_minus_constant_in_place;

const
  STEP = 4 * 250;           { 1000, folded }
  NEG = -3 * 7;             { -21, folded }

var
  vals: array[0..9] of Int64;
  q: QWord;
  i: Integer;
  x: Int64;
  w: LongWord;
  ni: Integer;

procedure Show(const tag: string; v: Int64);
begin
  Write(tag, '=', v, ' ');
end;

begin
  vals[0] := 0; vals[1] := -1; vals[2] := $FFFFFFFF; vals[3] := $100000000;
  vals[4] := $7FFFFFFF; vals[5] := -$80000000; vals[6] := -$100000000;
  vals[7] := High(Int64) - 3000; vals[8] := Low(Int64) + 3000; vals[9] := $FFFFF800;
  for i := 0 to 9 do
  begin
    x := vals[i];
    Show('+1', x + 1); Show('-1', x - 1); Show('+2047', x + 2047);
    Show('-2048', x - 2048); Show('+(-2048)', x + (-2048)); Show('-2047', x - 2047);
    Show('+2048', x + 2048); Show('-(-2048)', x - (-2048)); Show('+0', x + 0);
    Show('-0', x - 0); Show('+STEP', x + STEP); Show('-STEP', x - STEP);
    Show('+NEG', x + NEG); Show('-NEG', x - NEG);
    w := 5; ni := -7;
    Show('+w', x + LongWord(5)); Show('-w', x - LongWord(5));
    Show('+ni', x + Integer(-7)); Show('-ni', x - Integer(-7));
    Inc(x, 3); Show('inc', x); Dec(x, 700); Show('dec', x);
    WriteLn;
  end;
  q := $FFFFFFFF;
  WriteLn(q + 1, ' ', q + 2047, ' ', QWord($100000000) - 1, ' ', QWord(0) + 2047);
  q := High(QWord) - 5;
  WriteLn(q + 5, ' ', q - 2048, ' ', w + ni);
end.
