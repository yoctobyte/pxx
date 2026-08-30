program test_cdecl_bodied_wide;
{ Bodied `cdecl` procs with an argument block that OVERFLOWS the registers.

  bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets
  bug-a-riscv32-passes-stack-arguments-in-reverse-psabi-order

  THE FOURTH cdecl FILE, and like the other splits this one is an ABI boundary
  rather than tidiness:
    test_cdecl_bodied_sysv.pas   - x86-64 only; >6 params, 9-argument overflow.
    test_cdecl_bodied_cross.pas  - x86-64 + aarch64; up to 8 args per bank.
    test_cdecl_bodied_narrow.pas - every target, argument block <= 4 words.
    this file                    - TEN words, so only the targets that accept a
                                   >8-word signature at all: x86-64, i386 and
                                   riscv32. aarch64 and arm32 refuse one
                                   outright, so they cannot even compile it.
  Ten words cannot be bolted onto the narrow file: that file is capped at four
  words by arm32, and a file a target cannot COMPILE asserts nothing about it.

  TEN, NOT NINE, AND THAT IS THE ENTIRE POINT OF THE FILE. riscv32 placed
  overflow word k at [entry_sp + (pnWords-1-k)*4] -- descending -- where the
  psABI counts UP from the first stack word. At exactly NINE words there is one
  overflow word and (9-1-8)*4 = 0, so the two formulas COINCIDE and a
  nine-argument probe passes against a real C compiler. That probe was written
  first during this work and it passed. The bug is invisible until ten.

  So a nine-word case here would be a test that cannot fail, in a file whose
  whole purpose is the overflow tail. Anyone widening this file should add
  words, not shapes.

  WHAT THIS ASSERTS AND WHAT IT CANNOT. It asserts pxx caller <-> pxx callee
  agreement in all three shapes. It CANNOT by itself prove psABI conformance,
  because both ends of a pxx call share any convention error -- which is exactly
  how the riscv32 bug survived every internal probe. Conformance was established
  separately by disassembling both sides against riscv32-esp-elf-gcc 15.2.0
  (-mabi=ilp32) and is recorded in the ticket. This file is the regression
  guard for that fix, not its proof. }

type
  TFn10 = function(a,b,c,d,e,f,g,h,i,j: Integer): Integer; cdecl;

var failures: Integer = 0;
    checks: Integer = 0;

procedure Expect(got, want: Integer; const nm: AnsiString);
begin
  Inc(checks);
  if got <> want then
  begin
    writeln('FAIL ', nm, ': got ', got, ' want ', want);
    Inc(failures);
  end;
end;

{ Every argument is distinct and every one is READ, so a permuted argument list
  cannot cancel out. The two stack words carry the low digits deliberately: a
  swap of words 8 and 9 alone changes 100 to 109. }
function Cb10(a,b,c,d,e,f,g,h,i,j: Integer): Integer; cdecl;
begin
  Result := a*1000000000 + b*100000000 + c*10000000 + d*1000000 + e*100000
          + f*10000 + g*1000 + h*100 + i*10 + j;
end;

procedure TakeFn(fn: TFn10);
begin Expect(fn(1,2,3,4,5,6,7,8,9,10), 1234567900, 'ten words via fnptr'); end;

var f: TFn10;
begin
  { 1234567900: the eight register words contribute 1234567800, and the two
    STACK words contribute i*10 + j = 100. Swapping just those two gives
    1234567909 -- a different number, which is the property being tested. }
  TakeFn(@Cb10);
  Expect(Cb10(1,2,3,4,5,6,7,8,9,10), 1234567900, 'ten words direct');
  f := @Cb10;                     { the ASSIGNMENT shape the ir.inc reject keys on }
  Expect(f(1,2,3,4,5,6,7,8,9,10), 1234567900, 'ten words via assigned variable');

  if failures = 0 then
    writeln('CDECL-WIDE OK checks=', checks)
  else
    writeln('CDECL-WIDE FAILURES=', failures);
end.
