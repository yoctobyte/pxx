program CmpRightInPlace;
{ feature-opt-o3-register-pressure W1 slice 7: a fused compare reads its RIGHT
  operand in place -- `cmp rN, rM` when it is register-resident, `cmp rN,[rbp+off]`
  when it is an 8-byte frame local or param -- instead of staging it through rcx.

  Two new encodings, and the memory one is the risky half: ModRM mod=10 rm=101
  is rbp+disp32, so a wrong reg field compares the WRONG REGISTER against the
  slot, and a wrong displacement compares against the WRONG SLOT. Both produce a
  plausible number rather than a crash. So every variable below holds a distinct
  value, none is 0 or 1, and neighbouring slots hold values that would give a
  different answer if the offset were off by one slot.

  ONLY 8-byte operands are folded. A 4-byte one is loaded with `movsxd`, and
  folding that would mean a 32-bit compare plus the assumption that the left
  register holds a properly sign-extended value -- an invariant whose failure is
  a silently wrong comparison. The 4-byte rows here are therefore CONTROLS: they
  must keep working through the old rcx path, and they are what would move if
  the fold ever widened by accident.

  Values verified against FPC 3.2.2. Run at -O0 and -O3 against one expectation;
  the fold is -O3-gated, so -O0 cannot use either encoding. }

var
  gAcc: Int64;

function ByRef(var r: Int64; k: Int64): Int64;
begin
  { a by-ref param's slot holds a POINTER, so folding its address would compare
    the wrong thing entirely. LeafSymRcxLoadable excludes it; this row is here so
    that exclusion is asserted rather than assumed. }
  if k > r then ByRef := 1 else ByRef := 0;
end;

function Run(iters: LongInt): Int64;
var
  i: LongInt;
  a, b, c, d: Int64;        { 8-byte signed, adjacent slots, all distinct }
  blo, bhi: Int64;          { a BAND straddling a -- see the band rows below }
  u, v: QWord;              { 8-byte unsigned, both above 2^63 }
  s32, t32: LongInt;        { 4-byte controls -- NOT folded }
  acc: Int64;
begin
  acc := 0;
  a := 5000000000;
  b := -5000000001;
  c := 9223372036854775806;
  d := -9223372036854775807;
  u := 18446744073709551615;      { signed reading: -1 }
  v := 9223372036854775809;       { signed reading: -9223372036854775807 }
  blo := 4999999999;              { a - 1 }
  bhi := 5000000001;              { a + 1 }
  s32 := -2000000000;
  t32 := 2000000001;
  for i := 1 to iters do
  begin
    { 8-byte frame slots on the right -- the memory fold }
    if a > b then acc := acc + 1;
    if b < a then acc := acc + 2;
    if c > a then acc := acc + 4;
    if d < b then acc := acc + 8;
    if a <> c then acc := acc + 16;
    if c = c then acc := acc + 32;
    { unsigned 8-byte: u > v is TRUE unsigned, FALSE if read as signed }
    if u > v then acc := acc + 64;
    if v < u then acc := acc + 128;
    { the loop variable (resident) against an 8-byte slot }
    if i < a then acc := acc + 256;
    if a > i then acc := acc + 512;
    { A BAND around a, resident-left against an 8-byte slot. The rows above are
      individually insensitive to WHICH register the fold names: `a > b` with
      b = -5000000001 is true for almost any junk a wrong reg field could hold,
      so a wrong-register break passes them. Straddling a with a-1 and a+1 makes
      the pair true only for a register holding EXACTLY a, and only for the two
      slots blo/bhi -- so it catches a wrong reg field AND a wrong displacement.
      Verified: without it, both breaks are invisible. }
    if a > blo then acc := acc + 8192;
    if a < bhi then acc := acc + 16384;
    { The mirror band: non-resident left in rax against a RESIDENT right, i.e.
      the `cmp rax, rN` form. Same vacuity applies -- `b < a` holds for whatever
      junk a wrong rm field names -- so straddle a from the other side too. }
    if blo < a then acc := acc + 32768;
    if bhi > a then acc := acc + 65536;
    { 4-byte controls -- must stay on the rcx path }
    if s32 < t32 then acc := acc + 1024;
    if t32 > s32 then acc := acc + 2048;
    if s32 = -2000000000 then acc := acc + 4096;
  end;
  Run := acc;
end;

begin
  gAcc := Run(3);
  WriteLn('acc=', gAcc);
  gAcc := Run(1);
  WriteLn('one=', gAcc);
  gAcc := 42;
  WriteLn('byref=', ByRef(gAcc, 43), ByRef(gAcc, 41));
  WriteLn('done');
end.
