program test_signal_bss_alias;
{ A signal delivery must not disturb the program state that lives at BSS offset 0.

  WHY THIS EXISTS, and why test_signal_num.pas cannot replace it. The dispatch
  stub parks the signal number in BSS_SIG_NUM. That slot was allocated inside
  ONE arch's emitter, so on every other target it was 0 — aliased onto BSS[0],
  which is BSS_INITIAL_RSP, which is what ParamCount and ParamStr dereference.
  So a single delivered signal overwrote the saved initial stack pointer with the
  signal number, and the next ParamCount segfaulted.

  test_signal_num.pas CANNOT SEE THIS. Measured 2026-08-31 with the allocation
  deliberately put back in x86-64's emitter: it printed the correct
  `usr1=2 usr2=1 int=1 zero=0` on all four cross targets, because the store and
  the load both go to the aliased slot and agree with each other. The test's own
  `zero=0` guard — written precisely to catch "the slot is never written" — is
  blind to "the slot is somebody else's". A read-back test cannot detect a
  slot that is consistently wrong.

  So this test asserts on a NEIGHBOUR instead of on the slot: deliver a signal,
  then read something that lives at BSS[0]. With the bug, `after` segfaults on
  i386/arm32/aarch64 and prints nothing on riscv32. The check is
  before = after, not a literal count, so it does not care how the harness
  invokes it. }

const
{$ifdef CPUX86_64}
  SYS_gettid = 186; SYS_tkill = 200;
{$endif}
{$ifdef CPUAARCH64}
  SYS_gettid = 178; SYS_tkill = 130;   { asm-generic unistd }
{$endif}
{$ifdef CPURISCV32}
  SYS_gettid = 178; SYS_tkill = 130;   { asm-generic unistd }
{$endif}
{$ifdef CPUARM}
  SYS_gettid = 224; SYS_tkill = 238;   { ARM EABI }
{$endif}
{$ifdef CPUI386}
  SYS_gettid = 224; SYS_tkill = 238;
{$endif}

var hit, before, after: Integer; r, tid: Int64;
procedure Hook; begin hit := hit + 1; end;
begin
  before := ParamCount;
  SetSignalHandler(10, @Hook);   { SIGUSR1 }
  tid := __pxxrawsyscall(SYS_gettid);
  r := __pxxrawsyscall(SYS_tkill, tid, 10);
  after := ParamCount;
  WriteLn('hit=', hit, ' argv-intact=', before = after);
end.
