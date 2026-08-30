program Cmp32Fold;
{ feature-opt-o3-register-pressure W1 slice 8: when BOTH operands of a fused
  compare are 4-byte and of the same type, the right one is read in place with a
  32-BIT compare -- `cmp r12d, DWORD PTR [rbp+off]`, opcode 3B with no REX.W --
  instead of being sign-extended into rcx first. Slice 7 folded 8-byte operands
  only and declined this, which is why its own benchmark loop was unchanged.

  Dropping REX.W is the whole trick: a 32-bit compare reads exactly four bytes
  of the slot and exactly the low half of the register, so nothing depends on
  the upper half being correctly extended. That invariant does hold today, but
  the point is not to need it.

  Every row is a BAND, per the campaign's standing rule 4: `x > xlo` with a
  far-apart xlo is true for whatever junk a wrong register or slot would hold,
  so it cannot observe the bug this pass can introduce. Straddling x with x-1
  and x+1 makes the pair true only for a register holding exactly x and only for
  those two slots. Adjacent values, not distinct ones.

  Verified against FPC 3.2.2. Run at -O0 and -O3 against one expectation. }

var gAcc: Int64;

function Run(iters: LongInt): Int64;
var
  i, n: LongInt;
  x, xlo, xhi: LongInt;          { signed 4-byte, adjacent }
  u, ulo, uhi, uone: LongWord;   { unsigned 4-byte, all above 2^31 }
  big: Int64;                    { 8-byte -- the mixed-width control }
  acc: Int64;
begin
  acc := 0;
  x := 1000000; xlo := 999999; xhi := 1000001;
  u := 3000000000; ulo := 2999999999; uhi := 3000000001; uone := 1;
  big := 1000000;
  n := iters;
  for i := 1 to n do
  begin
    { signed band }
    if x > xlo then acc := acc + 1;
    if x < xhi then acc := acc + 2;
    { unsigned band -- both operands above 2^31, where a signed reading differs }
    if u > ulo then acc := acc + 4;
    if u < uhi then acc := acc + 8;
    { u > uone is TRUE unsigned and FALSE if the compare ever went signed:
      u read as a signed 32-bit value is negative. This row is the one that
      fails if dropping REX.W were ever paired with the wrong predicate. }
    if u > uone then acc := acc + 16;
    { mixed width: 8-byte against 4-byte must NOT fold -- the guard is identical
      TypeKind, and this row is what would move if it ever widened by accident }
    if big > xlo then acc := acc + 32;
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
