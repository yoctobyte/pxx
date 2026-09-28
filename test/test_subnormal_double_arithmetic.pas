{ SPDX-License-Identifier: Zlib }
program test_subnormal_double_arithmetic;
{ WHAT A TARGET DOES WITH SUBNORMAL DOUBLES, asserted rather than assumed.

  Measured 2026-09-28: `riscv32` and `xtensa` return ZERO from every arithmetic
  operation involving a subnormal double, and from every result that underflows
  into the subnormal range — there is no gradual underflow on those two. Every
  other target the compiler accepts (`x86_64`, `i386`, `arm32`, `aarch64`,
  `wasm32`) is IEEE-correct. `wasm32` is 32-bit and correct, so the population is
  not "32-bit targets": it is the two targets that lower double arithmetic onto
  compiler/builtin/softfloat.pas.

  AND THAT UNIT SAYS SO ITSELF, in its header, and has since it was written:
  "subnormals flush to zero (documented follow-up -- mul/div *rounding* of normal
  results is still correct, which is what decimal output depends on)". So this is
  a documented deferral, not a discovered defect, and nothing here should be read
  as calling it a bug. Whether softfloat should gain gradual underflow is the
  owner's call; flush-to-zero is a normal embedded float mode.

  WHAT WAS ACTUALLY MISSING was any statement of it outside that one file, and
  any test that would notice a change either way. test_softfloat_double.pas and
  test_softfloat_single.pas check the kernels against x86-64 hardware and
  TOLERATE the flush by construction (dFlushOK, FlushOK) -- the single one counts
  it, the double one does not count it at all. So `RESULT: PASS` on those rows
  never carried information about subnormals, in either direction. This file is
  the row that does. See docs/reference/known-issues.md and the LOGBOOK entry of
  2026-09-28.

  WHAT THIS FILE'S WIRING DOES NOT COVER: the Makefile's hosted xtensa arm is
  CALL0, as every hosted xtensa row is, so the WINDOWED ABI is unpinned here.
  frankd-90 measured both ABIs for the known-issues row and both flush, so the
  gap is documented rather than unknown -- but a windowed regression would not
  turn this row red, and anyone reading a green here should not conclude
  otherwise.

  THIS TEST IS GREEN ON BOTH MODES BY DESIGN, and it is not therefore toothless.
  It decides the mode from ONE probe and then requires every other row to AGREE
  with that mode. So what it actually asserts is CONSISTENCY, and the failures it
  can produce are the ones worth having:

    - a target that flushes some operations and not others (a half-implemented
      subnormal path, which is worse than either mode and is what a partial fix
      would look like);
    - a target whose mode CHANGES without the expectation being updated — the
      Makefile pins the expected mode per target, so a softfloat target that
      starts preserving subnormals turns its row red until someone writes down
      that it now does;
    - storage or comparison breaking, which is mode-independent: a subnormal must
      load, store and compare correctly on EVERY target, and does today.

  If the owner rules that softfloat should gain gradual underflow, the fix flips
  one word in this test's Makefile rows, not the test.

  WHY THE OPERANDS ARE BUILT FROM BIT PATTERNS AT RUN TIME: a literal like
  5e-324 folded at compile time is evaluated by the HOST's arithmetic, which is
  correct, so a constant-folded probe measures x86-64 and reports it as the
  target's answer. Every value here comes from PDouble(@bits)^ with bits
  assigned at run time.

  The mode word is printed, not inferred by the caller, so the Makefile row is a
  string comparison rather than a rule that has to be kept in step with this
  file's internals. }

var
  Failures: Integer;

procedure Check(const what: string; ok: Boolean);
begin
  if not ok then
  begin
    WriteLn('SUBNORMAL FAIL ', what);
    Failures := Failures + 1;
  end;
end;

{ The raw bits of a double, so a zero is distinguishable from a subnormal with a
  tiny mantissa without relying on float formatting (which the ESP bare profile
  does not have). }
function Bits(d: Double): Int64;
begin
  Bits := PInt64(@d)^;
end;

var
  bits: Int64;
  v, small, one, two, zero, r: Double;
  flush: Boolean;
begin
  Failures := 0;

  { 2**-1074, the minimum positive subnormal: exponent field 0, mantissa 1. }
  bits := 1;
  v := PDouble(@bits)^;
  { 2**-1019, normal, eight halvings above the subnormal boundary. }
  bits := Int64(4) shl 52;
  small := PDouble(@bits)^;
  one := 1.0;
  two := 2.0;
  zero := 0.0;

  { ---- MODE-INDEPENDENT: the value itself must survive and compare. ---- }
  Check('the subnormal did not survive assignment', Bits(v) = 1);
  Check('subnormal compares equal to zero', not (v = zero));
  Check('subnormal does not compare greater than zero', v > zero);
  Check('the normal control is not normal', ((Bits(small) shr 52) and $7FF) = 4);

  { ---- Decide the mode from ONE probe. ---- }
  flush := (v * one) = zero;
  if flush then
    WriteLn('SUBNORMAL-MODE flush')
  else
    WriteLn('SUBNORMAL-MODE gradual');

  { ---- Every other row must AGREE with that mode. ---- }
  if flush then
  begin
    Check('v * 2.0 not flushed', (v * two) = zero);
    Check('v + 0.0 not flushed', (v + zero) = zero);
    Check('v + v not flushed', (v + v) = zero);
    Check('v / 1.0 not flushed', (v / one) = zero);
    Check('v - 0.0 not flushed', (v - zero) = zero);
    { Gradual underflow: a normal value halved into the subnormal range. }
    r := small;
    r := r * 0.5; r := r * 0.5; r := r * 0.5; r := r * 0.5;
    r := r * 0.5; r := r * 0.5; r := r * 0.5; r := r * 0.5;
    Check('underflow result not flushed', r = zero);
  end
  else
  begin
    Check('v * 1.0 changed the value', Bits(v * one) = 1);
    Check('v * 2.0 is not 2**-1073', Bits(v * two) = 2);
    Check('v + 0.0 changed the value', Bits(v + zero) = 1);
    Check('v + v is not 2**-1073', Bits(v + v) = 2);
    Check('v / 1.0 changed the value', Bits(v / one) = 1);
    Check('v - 0.0 changed the value', Bits(v - zero) = 1);
    r := small;
    r := r * 0.5; r := r * 0.5; r := r * 0.5; r := r * 0.5;
    r := r * 0.5; r := r * 0.5; r := r * 0.5; r := r * 0.5;
    { 2**-1027: subnormal, so the exponent field is 0 and the mantissa is not. }
    Check('underflow did not produce a subnormal', (r <> zero) and (((Bits(r) shr 52) and $7FF) = 0));
  end;

  WriteLn('SUBNORMAL-CHECK failures=', Failures);
  if Failures > 0 then
    Halt(1);
end.
