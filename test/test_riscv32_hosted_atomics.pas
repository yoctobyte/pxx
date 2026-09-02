{ Hosted riscv32 atomics, via the A extension.

  riscv32 refused every __pxxatomic_* in user mode: the only primitive it had
  was the ESP arm's interrupt mask, which is a MACHINE-MODE trick, and the
  refusal generalised from the ESP32-C3 (RV32IMC, genuinely no A) to every
  rv32 core. A hosted core -- qemu's rv32gc, and every rv32 Linux part -- has
  the extension. So this ran on four targets and refused on the fifth, and
  lib/rtl/scheduler.pas, which takes a registration lock, could not be compiled
  for it at all.

  The encodings were checked against `clang --target=riscv32 -march=rv32ima`
  rather than derived; an encoder that is merely reasoned out assembles to
  SOMETHING, and something is not the instruction.
  bug-a-riscv32-and-xtensa-have-no-atomic-codegen (the hosted half) }
program test_riscv32_hosted_atomics;
uses palatomic;
var n, r: LongInt;
begin
  n := 10;
  r := InterLockedIncrement(n);          { AMOADD }
  WriteLn(r, '|', n);
  r := InterLockedExchange(n, 99);       { AMOSWAP }
  WriteLn(r, '|', n);
  { CAS is the one that needs the LR/SC pair rather than a single AMO -- no
    atomic memory op can express "store only if it still equals expected". }
  n := 42;
  if InterLockedCompareExchange(n, 7, 41) <> 42 then WriteLn('FAIL cas-miss return');
  if n <> 42 then WriteLn('FAIL cas must not store on a mismatch');
  r := InterLockedCompareExchange(n, 7, 42);
  WriteLn(r, '|', 42);
  if n <> 7 then WriteLn('FAIL cas must store on a match');
  WriteLn('ATOMICS OK');
end.
