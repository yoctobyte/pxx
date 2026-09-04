program test_cross_futex_through_the_pal;
{ The three futex wrappers on every target, and a row that catches a truncated
  timespec.

  palfutex.pas is deliberately dependency-free -- it cannot go through
  platform.pas, and its header says why -- so unlike the other private syscall
  tables deleted this week, the fix here was to FILL IN the missing arms rather
  than delete the table. Before 2026-09-04, riscv32 and xtensa had none
  (SYS_futex = -1, so all three calls answered -ENOSYS), and wasm32 refused all
  three BODIES at codegen: `__pxxrawsyscall(-1, ...)` is a runtime value in
  front of an instruction that is still EMITTED. Numbers measured under
  `qemu-<arch> -strace`: xtensa 191, riscv32 422 -- and riscv32 has NO plain
  futex at all, only futex_time64, because rv32 never provided the
  32-bit-time_t syscalls.

  MODES, because one of these rows has to be killed from outside to mean
  anything:

  `basic`    wake with nobody waiting (0), wait on a MISMATCH (-EAGAIN, -11),
             and a timed wait on a mismatch (-11 again, not a timeout). None of
             these blocks. On wasm32 all three are -38 and no syscall is emitted.

  `shortsec` a real timed wait that MATCHES, so it blocks and returns
             -ETIMEDOUT. This is the control for the row below: it proves the
             program reaches the call and comes back.

  `longsec`  tv_sec = 2^32 + 1. THE ROW THAT MEASURES THE TIMESPEC WIDTH, and
             it is the one row whose right answer DIFFERS BY TARGET -- which is
             what makes it able to fail. Three groups:

               64-bit tv_sec  x86-64, aarch64, riscv32   must NOT return
               32-bit tv_sec  i386, arm32, xtensa        returns -110 in ~1s
               no futex       wasm32                     -38, immediately

             riscv32 belongs to the FIRST group despite being a 32-bit target,
             and that is the entire point of this row: it has no plain futex at
             all, only futex_time64, so its tv_sec is 64-bit while its NativeInt
             is 4 bytes. With the shared `array[0..1] of NativeInt` it truncated
             to 1 and answered like i386. The 32-bit group truncating is CORRECT
             -- 2^32+1 seconds is unrepresentable in their ABI -- so asserting
             both directions pins the width instead of only catching one error.

  WHY THE OBVIOUS PROBE DOES NOT WORK, recorded because two of them were run
  first and both said the widths were identical. A 2-second timeout passes under
  BOTH widths: tv_sec fits the low word either way, and the kernel's tv_nsec
  then reads 8 bytes of stack that are zero on a fresh frame -- a legal 0ns. So
  the naive version waits the right 2s BY ACCIDENT. Dirtying the stack from a
  caller first did not move it either. Only a tv_sec that cannot fit in 32 bits
  separates them, and it separates them by minutes: 8s-killed versus 1117ms. }
uses palfutex;

var w: Integer; mode: string; r0, r1, r2: Integer;
begin
  mode := ParamStr(1);
  w := 7;
  if mode = 'basic' then
  begin
    r0 := PalFutexWake(@w, 1);
    r1 := PalFutexWait(@w, 999);
    r2 := PalFutexWaitTimeout(@w, 999, 1000);
    WriteLn('wake=', r0, ' wait=', r1, ' waitto=', r2);
  end
  else if mode = 'shortsec' then
    WriteLn('shortsec=', PalFutexWaitTimeout(@w, 7, 300000000))
  else if mode = 'longsec' then
  begin
    { INTO A VARIABLE FIRST. `WriteLn('longsec RETURNED ', <call>)` lowers to
      sequential writes, so the literal reached the pipe BEFORE the call was
      made -- a killed run still printed "longsec RETURNED" and a reader would
      have scored the failure as a pass. Measured, not guessed: that is exactly
      what the first version of this file did. }
    r0 := PalFutexWaitTimeout(@w, 7, 4294967297 * 1000000000);
    WriteLn('longsec RETURNED ', r0);
  end
  else
    WriteLn('usage: basic | shortsec | longsec');
end.
