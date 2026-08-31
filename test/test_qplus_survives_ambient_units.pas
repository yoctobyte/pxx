program test_qplus_survives_ambient_units;
{ {$Q+} left ON at `end.` -- which is the ordinary way to write it -- used to
  make arm32 and riscv32 FAIL TO COMPILE:

    pascal26:86: error: {$Q+}: PXXOverflow runtime helper not found
      in: ./compiler/builtin/softfloat.pas

  The switch is a lexer GLOBAL with one reset per compilation, so it leaked out
  of the user's source and into the compiler's own ambient runtime units.
  softfloat is pulled BEFORE builtinheap, so the checks it then emitted called a
  PXXOverflow that did not exist yet -- and only on the two targets that pull
  softfloat. The message blames "builtinheap not loaded", which is a red
  herring: `uses sysutils` loads it and the error does not change, because the
  problem is ORDER, not absence.

  The {$Q-} line at the bottom is therefore LOAD-BEARING BY ITS ABSENCE -- do
  not add one to tidy this file up. Moving {$Q-} above `end.` is exactly what
  made the old compiler pass, so a version of this test that turns the switch
  off before the end cannot fail on the broken binary and tests nothing.
  bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32 }
{$Q+}
var
  a, b, c: Integer;
  x, y: Int64;
begin
  { A float declaration is what pulls softfloat on the 32-bit targets, so this
    program has to contain one for the row to reach the bug at all. }
  WriteLn('start');

  { 32-bit overflow at the narrowing store. }
  a := 2147483647; b := 1;
  c := a + b;
  WriteLn('unreachable c=', c);

  x := 0; y := 0;
  WriteLn(x + y);
end.
