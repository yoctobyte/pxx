program ShrResidentZeroExt;
{ feature-opt-o3-fuse-the-resident-read-into-the-zero-extend-too-x86-64: a
  4-byte resident feeding a shift's leading ZERO-extend is read and widened by
  one `mov eax, rNd` instead of `mov rax, rN` + `mov eax, eax`.

  The sibling test (test_shr_resident_widen) covers the SIGN-extend flavour and
  carries `u: LongWord` as a control asserting that fold does not claim this
  site. That control was correct and is exactly why the gap survived: a control
  proving "this pass does not fire here" reads identically whether not-firing is
  right or is a missed opportunity. So this file asserts the same site from the
  other side, and the two `u` rows now mean different things on purpose.

  WHAT GOES WRONG IS NEVER A CRASH. `mov eax, rNd` is 89 /r with mod=11,
  reg=N (source), rm=000 -- so a wrong reg field reads the WRONG RESIDENT
  REGISTER and a missing REX.R reads rax instead of r8. Both give a plausible
  number. And if the deferred load is skipped while the widen site does not
  honour it, rax is never loaded at all and holds whatever the last statement
  left there.

  So the u/v/w rows are a BAND: three ADJACENT values whose shifted results
  differ by exactly 1, carrying distinct weights, so naming the wrong register
  moves the total by a small specific amount rather than by nothing.

  ZERO-extension itself is asserted by every band value being ABOVE 2^31. Read
  as signed 32 bits they are negative, so a sign-extend would give a number just
  under 2^63 where the correct answer is just under 2^31 -- the two cannot be
  confused by any amount of bad luck. `mod P` keeps both printable while staying
  sensitive to every bit.

  Controls that must NOT fold, each for its own reason:
    q   Int64     -- 8 bytes, so there is no leading widen at all
    s   Word      -- 2 bytes; its own load is a movzx from the low 16 bits,
                     which a 32-bit mov is not, so W1WidenLeftEligible declines
    a   LongInt   -- signed with a native-width result, which takes the OTHER
                     arm (movsxd); it is here so a change that collapsed the two
                     flavours into one encoding would show up as a wrong value

  Run at -O0 and -O3 against one expectation: the fold is -O3-gated, so -O0
  provably cannot use the encoding and one answer covers both. }

const
  P = 1000000007;

var
  gAcc: Int64;

function Run(iters: LongInt): Int64;
var
  i, k: LongInt;
  u, v, w: LongWord;      { the BAND: adjacent, all above 2^31 }
  m: LongWord;            { 2^32-1 -- the top of the unsigned range }
  a: LongInt;             { signed, native-width result: the movsxd arm }
  q: Int64;               { 8-byte: no leading widen }
  s: Word;                { 2-byte: wrong extension width if folded }
  acc: Int64;
begin
  acc := 0;
  u := 4000000000;
  v := 4000000002;
  w := 4000000004;
  m := 4294967295;
  a := -1000000001;
  q := -1000000001;
  s := 60000;
  k := 3;
  for i := 1 to iters do
  begin
    { the band -- distinct weights, so a wrong register field is a specific
      wrong total and not a coincidence }
    acc := acc + ((u shr 1) mod P);
    acc := acc + ((v shr 1) mod P) * 2;
    acc := acc + ((w shr 1) mod P) * 4;
    acc := acc + ((m shr 3) mod P) * 8;
    { a VARIABLE count -- the other arm carrying the pre-decision, where the
      right operand's load must leave rax alone while the left is deferred }
    acc := acc + ((u shr k) mod P) * 256;
    acc := acc + ((v shr k) mod P) * 512;
    { controls }
    acc := acc + ((a shr 1) mod P) * 16;
    acc := acc + ((q shr 1) mod P) * 32;
    acc := acc + ((s shr 1) mod P) * 64;
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
