program test_div_by_zero_raises_on_every_target;
{ Integer `div` / `mod` by zero raises on EVERY backend, not just x86-64.

  Before this, only x86-64 emitted a pre-divide check. The other backends let
  the hardware decide and each ISA has a different opinion, so the same Pascal
  program answered a different wrong number per target -- the bug class this
  project exists to hunt:

      i386    1 div 0 = -1          (and 17 mod 0 = -17)
      arm32   1 div 0 = -1
      aarch64 1 div 0 = 0           (ARM spec: zero divisor yields 0)
      riscv32 1 div 0 = -1, 17 mod 0 = 17, unsigned = 4294967295
                                    (RISC-V spec: all-ones quotient, dividend as remainder)

  Settled by decide-int-div-zero-behavior-unification (user, 2026-07-20, option
  1: RE 200 everywhere).

  Both widths and both signednesses are covered because they are DIFFERENT CODE
  on the 32-bit targets: 64-bit div/mod there is a software long-division
  routine, not an instruction, and it needed its own guard.

  The non-zero rows carry as much weight as the raising ones -- the fix inserts a
  test in front of the hottest arithmetic in the compiler, and a test that only
  checked the zero case would pass even if ordinary division broke.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 produces every value below and raises on every
  row marked as raising. }
{$mode objfpc}{$H+}
uses sysutils;
var
  i32a, i32b, i32c: Integer;
  c32a, c32b, c32c: Cardinal;
  i64a, i64b, i64c: Int64;
  q64a, q64b, q64c: QWord;
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

  { --- ordinary division, every width and signedness --- }
  i32a := 17;  i32b := 5;  Chk('i32 div',    i32a div i32b, 3);
  i32a := 17;  i32b := 5;  Chk('i32 mod',    i32a mod i32b, 2);
  i32a := -17; i32b := 5;  Chk('i32 div neg', i32a div i32b, -3);
  i32a := -17; i32b := 5;  Chk('i32 mod neg', i32a mod i32b, -2);
  c32a := 17;  c32b := 5;  Chk('c32 div',    c32a div c32b, 3);
  c32a := 17;  c32b := 5;  Chk('c32 mod',    c32a mod c32b, 2);

  { 64-bit is a SOFTWARE long division on the 32-bit targets -- its own guard }
  i64a := 17000000000;  i64b := 5;  Chk('i64 div', i64a div i64b, 3400000000);
  i64a := 17000000000;  i64b := 5;  Chk('i64 mod', i64a mod i64b, 0);
  i64a := -17000000000; i64b := 5;  Chk('i64 div neg', i64a div i64b, -3400000000);
  q64a := 17000000000;  q64b := 5;  Chk('q64 div', q64a div q64b, 3400000000);

  { --- ...and a zero divisor raises, on every target and in every path --- }
  i32a := 17; i32b := 0;
  try i32c := i32a div i32b; writeln('FAIL i32 div 0: got ', i32c); Inc(fails);
  except on e: Exception do ; end;

  i32a := 17; i32b := 0;
  try i32c := i32a mod i32b; writeln('FAIL i32 mod 0: got ', i32c); Inc(fails);
  except on e: Exception do ; end;

  c32a := 17; c32b := 0;
  try c32c := c32a div c32b; writeln('FAIL c32 div 0: got ', c32c); Inc(fails);
  except on e: Exception do ; end;

  c32a := 17; c32b := 0;
  try c32c := c32a mod c32b; writeln('FAIL c32 mod 0: got ', c32c); Inc(fails);
  except on e: Exception do ; end;

  i64a := 17000000000; i64b := 0;
  try i64c := i64a div i64b; writeln('FAIL i64 div 0: got ', i64c); Inc(fails);
  except on e: Exception do ; end;

  i64a := 17000000000; i64b := 0;
  try i64c := i64a mod i64b; writeln('FAIL i64 mod 0: got ', i64c); Inc(fails);
  except on e: Exception do ; end;

  q64a := 17000000000; q64b := 0;
  try q64c := q64a div q64b; writeln('FAIL q64 div 0: got ', q64c); Inc(fails);
  except on e: Exception do ; end;

  q64a := 17000000000; q64b := 0;
  try q64c := q64a mod q64b; writeln('FAIL q64 mod 0: got ', q64c); Inc(fails);
  except on e: Exception do ; end;

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.
