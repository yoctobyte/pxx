program ShrResidentWiden;
{ feature-opt-o3-fuse-resident-read-and-widen-into-movsxd (W1 slice 10): a
  4-byte SIGNED resident feeding a shift's LEADING sign-extend is read and
  widened by one `movsxd rax, rNd` instead of `mov rax, rN` + `cdqe`.

  What can go wrong is never a crash. movsxd's ModRM is mod=11 reg=000 rm=N,
  so a wrong rm field reads the WRONG RESIDENT REGISTER, and a missing REX.B
  reads rsp's slot instead of r12's -- both give a plausible number. Worse, if
  the deferred load is skipped and the widen site does NOT honour it, rax is
  never loaded at all and holds whatever the previous statement left there.

  So: the a/b/c rows are a BAND -- three ADJACENT values whose shifted results
  differ by exactly 1 -- and they carry distinct weights, so naming the wrong
  one of them moves the total by a small, specific amount rather than by
  nothing. Far-apart values would not catch it: -1000000002 shr 1 and
  -2000000000 shr 1 are both "some huge number", and any of them satisfies a
  test that only checks the sign.

  Sign-extension itself is asserted by the values being NEGATIVE: a 4-byte
  negative widened to 64 bits and shifted right logically gives a number just
  under 2^63, whereas a DROPPED extension gives one just under 2^31. A `mod`
  by a large prime is what makes both fit in the printed answer while staying
  sensitive to every bit.

  Controls that must NOT fold, each for its own reason:
    q   Int64      -- 8 bytes, so there is no leading widen at all
    s   SmallInt   -- 2 bytes; its own load is a movsx from the low 16 bits,
                      which movsxd is not, so W1WidenLeftEligible must decline
    u   LongWord   -- unsigned, so the arm zero-extends (`mov eax,eax`) and the
                      fold's predicate must not claim that site

  Run at -O0 and -O3 against one expectation; the fold is -O3-gated, so -O0
  cannot use the encoding.

  ORACLE, and a second control for free. In this dialect a Pascal shift runs at
  NATIVE width, so `a shr 1` on a LongInt is the SIGN-EXTENDED 64-bit value
  shifted -- which is the whole reason a leading cdqe exists to fuse. FPC keeps
  the operand's 32-bit width and answers differently; that is the deliberate
  divergence `--strict-fpc` exists for, and under that flag pxx reproduces FPC
  3.2.2 exactly (verified, all rows). It is also a CONTROL: strict mode tags the
  result 4 bytes, so W1LeadingCdqe is false and this fold cannot fire at all.
  Hence two expectations here, not one -- the default answer and the strict-fpc
  answer -- and BOTH must hold at -O0 and -O3 alike. }

const
  P = 1000000007;

var
  gAcc: Int64;

function Run(iters: LongInt): Int64;
var
  i, k: LongInt;
  a, b, c: LongInt;       { the BAND: adjacent, so results differ by 1 }
  e: LongInt;             { INT32_MIN -- the edge of the widened range }
  u: LongWord;            { unsigned 4-byte: zero-extend path, not this fold }
  q: Int64;               { 8-byte: no leading widen }
  s: SmallInt;            { 2-byte: wrong extension width if folded }
  acc: Int64;
begin
  acc := 0;
  a := -1000000002;
  b := -1000000001;
  c := -1000000000;
  e := -2147483648;
  u := 4000000000;
  q := -1000000001;
  s := -30000;
  k := 3;
  for i := 1 to iters do
  begin
    { the band -- distinct weights, so a wrong register field is a specific
      wrong total and not a coincidence }
    acc := acc + ((a shr 1) mod P);
    acc := acc + ((b shr 1) mod P) * 2;
    acc := acc + ((c shr 1) mod P) * 4;
    acc := acc + ((e shr 3) mod P) * 8;
    { a VARIABLE count -- the other arm that carries the pre-decision (the
      right operand goes through EmitLoadVarRcx, which must leave rax alone
      while the left load is still deferred) }
    acc := acc + ((a shr k) mod P) * 256;
    acc := acc + ((b shr k) mod P) * 512;
    { the loop variable itself, resident and non-negative }
    acc := acc + ((i shr 1) mod P) * 128;
    { controls }
    acc := acc + ((u shr 1) mod P) * 16;
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
