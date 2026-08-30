program ImulResidentLeft;
{ feature-opt-o3-register-pressure W1 slice 6: a register-RESIDENT left operand
  multiplied by a CONSTANT uses imul's three-operand form (`imul rax, r12, k`)
  instead of `mov rax, r12` first.

  imul is the only form in the -O1 immediate-fold arm that can do this. The
  other five there -- add/sub/and/or/xor -- are short accumulator encodings
  that both read and write rax, so a resident left has to be moved and they are
  UNCHANGED. This file exercises all six side by side for exactly that reason:
  the five controls must keep producing the same answers while the sixth
  changes encoding, so a mistake in the imul arm cannot hide behind them.

  What a wrong encoding does here: `imul rax, rN, imm32` puts the SOURCE in the
  r/m field (REX.B) and the DESTINATION in the reg field, the opposite way round
  from the compare emitters in this campaign. Swap them and it multiplies the
  wrong register, so every variable holds a distinct value and none is 0 or 1.

  Constants cover both signs, both sides of the 32-bit boundary, and the imm32
  extremes -- imul sign-extends its immediate to 64 bits, and a mangled REX.W
  would multiply 32 bits instead, which small positive numbers cannot show.

  The multiplications sit in a loop because residency is only assigned to hot
  locals; outside one, none of this is reached.

  CONTROL: the pass is -O3-gated, so the same program at -O0 provably cannot use
  the three-operand form. The Makefile runs both against one expectation.
  Values verified against FPC 3.2.2. }

var gAcc: Int64;

function Run(iters: LongInt): Int64;
var
  i: LongInt;
  a: Int64;
  c: LongInt;
  u: LongWord;
  acc: Int64;
begin
  acc := 0;
  a := 3000000007;
  c := -12345;
  u := 4000000000;
  for i := 1 to iters do
  begin
    { imul, three-operand form at -O3 }
    acc := acc + a * 3;
    acc := acc + a * (-7);
    acc := acc + c * 100000;
    acc := acc + c * (-100000);
    acc := acc + Int64(u) * 2;
    acc := acc + i * 2147483647;      { imm32 max }
    acc := acc + i * (-2147483648);   { imm32 min }
    acc := acc + a * 1;
    acc := acc + a * 0;

    { the five arms that must NOT change: short accumulator encodings }
    acc := acc + (a + 1000);
    acc := acc + (a - 1000);
    acc := acc + (c and $FF00);
    acc := acc + (c or $00FF);
    acc := acc + (c xor $5A5A);
  end;
  Run := acc;
end;

begin
  gAcc := Run(4);
  WriteLn('acc=', gAcc);
  gAcc := Run(1);
  WriteLn('one=', gAcc);
  WriteLn('done');
end.
