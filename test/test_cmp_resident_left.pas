program CmpResidentLeft;
{ feature-opt-o3-register-pressure W1 slice 5: a register-RESIDENT left operand
  feeding a compare is read in place (`cmp r12, rcx` / `cmp r12, imm32`) instead
  of being funnelled through rax first.

  Two encodings are new and both are easy to get subtly wrong:

    reg form  `4C 3B C1|reg`  -- REX.R plus the reg field, where the rax form
                                 uses neither.
    imm form  `49 81 F8|reg`  -- rax has a SHORT accumulator encoding (48 3D)
                                 that no other register has, so this is not the
                                 same instruction with a different register: it
                                 is a different opcode with a /7 extension.

  A wrong REX or a wrong ModRM field compares the WRONG REGISTER, which is the
  failure this file has to catch. That means comparing values that differ from
  each other in ways a register mix-up would show -- so every variable below
  holds a distinct value, and none is 0 or 1.

  Sign is the other half. `cmp` sign-extends imm32 to 64 bits, and a mangled
  REX.W would compare 32 bits instead; both are invisible on small positive
  numbers. Hence negatives, values astride the 32-bit boundary, and unsigned
  values above 2^31 whose signed reading is negative.

  The comparisons sit in a loop because residency is only assigned to hot
  locals -- outside one, none of this code is reached at all.

  CONTROL: the pass is gated to -O3, so the SAME program at -O0 cannot use
  either new encoding. The Makefile runs both and pins them to one expected
  output, so a wrong encoding shows up as two optimisation levels disagreeing
  rather than as a number with no oracle. Values verified against FPC 3.2.2. }

var
  gAcc: Int64;

function Run(iters: LongInt): Int64;
var
  i: LongInt;
  a, b: Int64;          { astride the 32-bit boundary, one negative }
  c, d: LongInt;        { 32-bit signed, one negative }
  u, v: LongWord;       { unsigned, both above 2^31 so signed reading is < 0 }
  s: ShortInt;
  acc: Int64;
begin
  acc := 0;
  a := 5000000000;      { > 2^32 }
  b := -5000000001;
  c := -2000000000;
  d := 2000000001;
  u := 4000000000;      { signed reading: -294967296 }
  v := 3000000000;      { signed reading: -1294967296 }
  s := -100;
  for i := 1 to iters do
  begin
    { register form: resident left against a non-constant right }
    if a > b then acc := acc + 1;
    if b < a then acc := acc + 2;
    if c < d then acc := acc + 4;
    if d >= c then acc := acc + 8;
    if u > v then acc := acc + 16;        { unsigned: 4e9 > 3e9 }
    if v <= u then acc := acc + 32;
    if a <> b then acc := acc + 64;
    if c = c then acc := acc + 128;

    { immediate form: resident left against a constant, both signs and both
      sides of the 32-bit boundary }
    if c < 0 then acc := acc + 256;
    if d > 0 then acc := acc + 512;
    if c <= -2000000000 then acc := acc + 1024;
    if d >= 2000000001 then acc := acc + 2048;
    if s < 0 then acc := acc + 4096;
    if s = -100 then acc := acc + 8192;
    if i >= 1 then acc := acc + 16384;
    if i <> 0 then acc := acc + 32768;

    { the loop variable itself as a resident left -- this is the shape the
      hot-loop measurement was taken on }
    if i <= iters then acc := acc + 65536;
  end;
  Run := acc;
end;

begin
  gAcc := Run(3);
  WriteLn('acc=', gAcc);
  gAcc := Run(1);
  WriteLn('one=', gAcc);
  WriteLn('done');
end.
