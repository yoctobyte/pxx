program LeafSymBinops;
{ The right operand of every binop here is a LEAF SYMBOL, which is the shape the
  -O3 aarch64 collapse now loads straight into x1. Non-commutative ops matter
  most: they are the ones that would give a plausible wrong answer rather than a
  crash if the operands ended up the wrong way round. }
{$Q+}{$R+}
var
  gA, gB: LongInt;
  gI: Int64;
  gU: LongWord;
  gS: SmallInt;
  gY: Byte;
  gBool1, gBool2: Boolean;
  gD1, gD2: Double;

procedure NonCommutative(var pA: LongInt; pB: LongInt);
var lA: LongInt;
begin
  lA := 1000;
  { local op leaf-local, local op leaf-param, local op leaf-global, all three }
  WriteLn('sub  ', lA - pB, ' ', lA - gB, ' ', pA - gB);
  WriteLn('div  ', lA div pB, ' ', lA div gB, ' ', pA div gB);
  WriteLn('mod  ', lA mod pB, ' ', lA mod gB, ' ', pA mod gB);
  WriteLn('shl  ', lA shl gY, ' ', pA shl gY);
  WriteLn('shr  ', lA shr gY, ' ', pA shr gY);
  WriteLn('lt   ', lA < pB, ' ', lA < gB, ' ', pA < gB);
  WriteLn('le   ', lA <= pB, ' ', lA <= gB, ' ', pA <= gB);
  WriteLn('gt   ', lA > pB, ' ', lA > gB, ' ', pA > gB);
  WriteLn('ge   ', lA >= pB, ' ', lA >= gB, ' ', pA >= gB);
end;

procedure Commutative;
begin
  WriteLn('add  ', gA + gB, ' ', gA + gI, ' ', gS + gY);
  WriteLn('mul  ', gA * gB, ' ', gS * gY);
  WriteLn('and  ', gA and gB, ' ', gU and gU);
  WriteLn('or   ', gA or gB);
  WriteLn('xor  ', gA xor gB);
  WriteLn('eq   ', gA = gB, ' ', gBool1 = gBool2);
  WriteLn('neq  ', gA <> gB, ' ', gBool1 <> gBool2);
end;

procedure Mixed;
var i, acc: Int64;
begin
  acc := 0;
  for i := 1 to 50 do
  begin
    { right operand is a global leaf on every one of these }
    acc := acc + i * gA;
    acc := acc - gB;
    acc := acc xor gI;
    if acc > gI then acc := acc div gA;
    if acc < gB then acc := acc + gU;
  end;
  WriteLn('mixed ', acc);
end;

begin
  gA := 7; gB := 13; gI := 1234567890123; gU := 4000000000;
  gS := -300; gY := 3;
  gBool1 := True; gBool2 := False;
  gD1 := 1.5; gD2 := 0.25;

  Commutative;
  NonCommutative(gA, gB);
  Mixed;

  { signed/unsigned narrow right operands, where sz/sgn in the loader matters }
  WriteLn('narrow ', gA - gS, ' ', gA - gY, ' ', gI - gS, ' ', gI - gY);
  WriteLn('float  ', (gD1 - gD2):0:6, ' ', (gD1 / gD2):0:6);
end.
