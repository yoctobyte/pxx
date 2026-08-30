program CmpBothInPlace;
{ feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen:
  the aarch64 port of W1 slices 5 and 7, which collapse into ONE arm there.
  `cmp Xn, Xm` on aarch64 IS `subs xzr, Xn, Xm` -- both sources are free
  register fields -- so a register-resident LEFT and a register-resident RIGHT
  can each be read where they live, and both staging moves disappear. x86-64
  needed two slices and a memory form to say the same thing.

  What can go wrong is a plausible number, never a crash: a wrong Rn field
  compares the WRONG RESIDENT against the right operand, a wrong Rm field the
  reverse, and the two default to x0/x1 when unfolded, so an off-by-one in
  either direction silently compares a staged value against itself.

  So every comparison here is a BAND -- adjacent values, one apart -- and the
  bands straddle from BOTH sides, because a one-sided row is satisfied by
  almost any junk a wrong register could hold. Distinct weights make a wrong
  register a specific wrong total rather than a coincidence.

  THE ROW THAT PRICES THE SCOPE GUARD is `cplx`: a resident left against a
  COMPLEX right subtree. The left load may only be skipped when the right is a
  constant or a leaf symbol; the general arm pushes x0 across an arbitrary
  right evaluation, and a left that was never materialised gets pushed as
  whatever x0 happened to hold. No other row can see that -- every other right
  operand here is a leaf or a constant, which is exactly the arm that is safe.

  Run at -O0 and -O3 against one expectation, on BOTH targets: the fold is
  -O3-gated and aarch64-only, so x86-64 and -O0 are three independent controls
  on the same numbers. Values verified against FPC 3.2.2. }

var
  gAcc: Int64;

function Mix(x, y: Int64): Int64;
begin
  { deliberately not inlinable-looking, and deliberately cheap: this is the
    complex right operand, not the thing being measured. }
  Mix := (x * 3) - (y * 2);
end;

function Run(iters: LongInt): Int64;
var
  i: LongInt;
  a, b, c: Int64;      { the band: c = a + 1 = b + 2 }
  u, v: QWord;         { unsigned, both above 2^63 and one apart }
  acc: Int64;
begin
  acc := 0;
  a := 4000000000;
  b := 4000000001;
  c := 4000000002;
  u := 18446744073709551614;
  v := 18446744073709551615;
  for i := 1 to iters do
  begin
    { resident vs resident, straddled from both sides -- true only if BOTH
      register fields name exactly the intended pair }
    if a < b then acc := acc + 1;
    if b < c then acc := acc + 2;
    if c > b then acc := acc + 4;
    if b > a then acc := acc + 8;
    if a <> b then acc := acc + 16;
    if b = b then acc := acc + 32;
    { unsigned, one apart, above 2^63 where a signed reading flips the answer }
    if u < v then acc := acc + 64;
    if v > u then acc := acc + 128;
    { resident left vs CONSTANT right -- the other folding arm }
    if a > 3999999999 then acc := acc + 256;
    if a < 4000000001 then acc := acc + 512;
    { the loop counter, resident and narrow, against a wide resident }
    if i < a then acc := acc + 1024;
    if a > i then acc := acc + 2048;
    { THE SCOPE-GUARD ROW: resident left, COMPLEX right. Mix(b, a) is
      3b - 2a = a + 3 for this band, so the comparison sits one step outside
      it -- close enough that a wrongly-skipped left load cannot land on the
      right answer by accident. }
    if a < Mix(b, a) then acc := acc + 4096;
    if Mix(b, a) > c then acc := acc + 8192;
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
