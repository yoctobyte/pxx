program test_double_to_integer_lvalue_rounds;
{ A FLOAT ASSIGNED TO AN INTEGER LVALUE MOVED THE BITS. `D := 4.7; Co := D`
  with `Co: Comp` printed 4616977747989548237 -- the IEEE-754 payload read as
  an integer -- where fpc 3.2.2 prints 5.

  This is the SIBLING of test_variant_double_to_integer_rounds.pas, and it is
  the arm that stayed broken: that test fixed `i := v` where v is a VARIANT
  holding a double, and asserted its own scope carefully, but the plain
  `i := <double>` next to it was never a variant conversion and so was never
  covered. One shape, two paths, and the second one is the one that stays
  wrong (normalise-dont-special-case.md).

  The conversion lives in the BACKEND: the IR is load_sym -> store_sym with no
  conversion node either way. Only x86-64 and aarch64 had a float->int store
  arm at all, and x86-64's is CProgramMode-gated, so in Pascal mode five
  backends had none. Fixed in ir.inc's AN_ASSIGN arm instead -- the shared
  layer -- by wrapping the RHS in the -204 Round intrinsic, which all seven
  backends already implement.

  ORACLE. Only the Comp rows have one: fpc 3.2.2 REFUSES `I := D` outright
  ("Incompatible types: got Double expected SmallInt"), and accepts it for
  Comp only because Comp is a real-valued type there. So:
    * Comp rows       -- measured against fpc 3.2.2, which prints
                         5 / 2 / 4 / -5 / -2 / 0 / 2 for the rows below
                         (rendered 5.000000000000000000E+0000 etc, because
                         FPC's Comp is real-valued and ours aliases Int64 --
                         a separate type-identity question, not this bug).
    * every other row -- pxx accepting what FPC rejects, which is not a defect.
                         The VALUE is chosen to agree with the variant sibling
                         above: round half-to-EVEN, one rule for both paths.

  DISCRIMINATION. With the bug present this test reports 19 failures against
  the pinned compiler, so the rows below are a guard that can fail. But note
  what the control also showed: a 32-bit target stores the LOW HALF of the
  payload, and that half is 0 for a great many doubles -- `I := 7.5` answered
  0, not a big number. So ANY row expecting 0 into a 32-bit target is
  non-discriminating here, not merely the literal-zero one. There is exactly
  one such row and it is labelled where it sits; do not add more without
  saying so. }
var
  D: Double;
  S: Single;
  E: Extended;
  Co: Comp;
  I: Integer;
  L: Int64;
  By: Byte;
  Wo: Word;
  Sm: SmallInt;
  fails: Integer;

procedure Chk(const what: string; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { --- the ticket's own shape: Comp, the one fpc compiles --- }
  D := 4.7;  Co := D;  Chk('comp 4.7',  Co,  5);
  D := 2.5;  Co := D;  Chk('comp 2.5',  Co,  2);
  D := 3.5;  Co := D;  Chk('comp 3.5',  Co,  4);
  D := 1.5;  Co := D;  Chk('comp 1.5',  Co,  2);
  D := 0.5;  Co := D;  Chk('comp 0.5',  Co,  0);
  D := -4.7; Co := D;  Chk('comp -4.7', Co, -5);
  D := -2.5; Co := D;  Chk('comp -2.5', Co, -2);
  D := -3.5; Co := D;  Chk('comp -3.5', Co, -4);

  { --- every integer width takes the same rule --- }
  D := 12.6;  I  := D;  Chk('Integer',  I,  13);
  D := 12.4;  L  := D;  Chk('Int64',    L,  12);
  D := 200.6; By := D;  Chk('Byte',     By, 201);
  D := 999.5; Wo := D;  Chk('Word',     Wo, 1000);
  D := -3.6;  Sm := D;  Chk('SmallInt', Sm, -4);

  { --- the source width does not change the rule --- }
  S := 7.5;  I := S;  Chk('Single 7.5',   I, 8);
  S := 6.5;  I := S;  Chk('Single 6.5',   I, 6);
  E := 8.5;  I := E;  Chk('Extended 8.5', I, 8);
  E := 9.5;  I := E;  Chk('Extended 9.5', I, 10);

  { --- an expression RHS, not just a bare load --- }
  D := 2.0;  I := D + 1.5;  Chk('expr 3.5', I, 4);
  D := 7.0;  I := D / 2;    Chk('expr 3.5 div', I, 4);

  { --- NOT DISCRIMINATING, and here on purpose: 0.0's payload is 0 and so is
        the low half a 32-bit target would have taken, so this row passes with
        the bug present (measured against the pin). It guards the value, not
        the fix. Never count it as coverage. --- }
  D := 0.0;  I := D;  Chk('zero', I, 0);

  { --- scope, asserted so a later change cannot hide behind this test --- }
  D := 4.7;  Chk('Trunc still truncates', Trunc(D), 4);
  D := -4.7; Chk('Trunc negative',        Trunc(D), -4);
  D := 2.5;  Chk('Round unchanged',       Round(D), 2);
  I := 5;    L := I;   Chk('int to int untouched', L, 5);
  D := 9.5;  D := D;   Chk('float to float untouched', Trunc(D * 2), 19);

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
