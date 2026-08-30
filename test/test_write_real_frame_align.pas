{ WriteLn of a real, which is the shape that exposed an unaligned frame slot.

  The float writers (PxxSciDigits17, PxxIntDDigits, PxxFracDigits) each hold a
  hidden aggregate-result temp reserved as AllocArray('', tyUInt8, 0, n-1). A
  byte array asked TypeAlign about its ELEMENT and got 1, so the slot landed at
  whatever offset the frame had reached -- eight of them, all odd -- and every
  backend's prologue nil-inits such a slot with a FOUR-BYTE store.

  Five backends never complained: x86-64 and i386 allow unaligned word access in
  hardware, qemu-riscv32/arm emulate it silently. Xtensa traps, so `WriteLn(d)`
  died with SIGBUS after printing the literal prefix and before the number,
  while Str(d:0:2,s) of the same value was correct -- the formatting was never
  the problem, the frame slot was.

  An alignment rule enforced only by hardware is not enforced (frankS).
  bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot }
program test_write_real_frame_align;
var
  d: Double;
  s: Single;
begin
  d := 7;
  WriteLn('A');
  WriteLn('B ', d);
  d := -0.125;
  WriteLn('C ', d);
  s := 3.5;
  WriteLn('D ', s);
  { deliberately no unnamed-constant division here: `1.0/3.0` renders at a
    different WIDTH under FPC than under pxx, which is a separate defect
    (bug-a-write-picks-a-different-float-width-per-target-and-both-disagree-with-fpc)
    and would make this test a moving target for a bug it does not guard. }
  WriteLn('F ', d:0:3);
end.
