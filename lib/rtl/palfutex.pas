{ SPDX-License-Identifier: Zlib }
unit palfutex;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ The three futex syscall wrappers, on their own, depending on nothing.

  They used to live in palthread next to __pxxclone — and reaching that unit at
  all fails to compile without --threadsafe, because the default heap/ARC/console
  runtime is not thread-safe. That gate is right for thread *creation* and wrong
  for *waiting on a word*, which needs no thread-safe heap and no threads at all
  to compile. The cost was structural: syncobjs' TCriticalSection had to be a
  spinlock rather than a blocking mutex (`uses syncobjs` must not start demanding
  --threadsafe — Synapse's ssfpc.inc is exactly the caller that would break, and
  it does no threading), and palatomic had to be its own unit for the same
  reason. bug-b-futex-helpers-are-trapped-behind-pxxclone.

  So this unit is deliberately dependency-free, like palatomic: raw syscalls and
  nothing else. Pascal `uses` is not transitive, so every caller of PalFutex*
  needs its own `uses palfutex` — palthread re-exports nothing.

  Linux only. A target with no futex answers -ENOSYS at RUNTIME rather than
  failing the compile, so a unit that merely *mentions* a futex does not break a
  build for a target that never blocks.

  BUT "-1 as the syscall number" IS NOT THAT SHAPE ON A TARGET WITH NO SYSCALL
  LOWERING, and that is what it was until 2026-09-04. `__pxxrawsyscall(-1, ...)`
  is a runtime value in front of an instruction that is still EMITTED, so wasm32
  refused all three BODIES at codegen and any module reaching them trapped. The
  wasm32 arm below returns -ENOSYS without emitting a syscall at all, which is
  the difference between a defined failure and a refusal. Same mistake, same
  week, as sysutils.Sleep and pxxcio's exit.

  THE NUMBERS FOR riscv32 AND xtensa WERE MEASURED, not copied: one syscall per
  process under `qemu-<arch> -strace`, every argument 2147483647 so the call is
  inert whatever it turns out to be, sweeping for the one qemu NAMES futex. That
  is the method platform/posix/platform_backend.pas's xtensa block documents,
  and its limit is recorded there too -- it is an oracle about qemu, not about a
  kernel on real hardware, and every test of these targets in this tree runs
  under qemu. Positive control on each: read and write come back as the values
  this repo had established independently.

  riscv32 IS THE INTERESTING ONE. It has NO plain futex -- the sweep found
  nothing at 98 or anywhere near it, and only `futex_time64` at 422 -- because
  rv32 never provided the 32-bit-time_t syscalls
  (bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall
  is the same fact costing the whole time family). So its timeout struct is a
  64-BIT timespec, and PalFutexWaitTimeout's `array[0..1] of NativeInt` -- four
  bytes per field there -- would have handed the kernel half a value. The width
  is per target below, not shared. }

interface

{ Sleep while addr^ still equals expected (FUTEX_WAIT). Returns the raw syscall
  result. Used to build mutexes/events on top. }
function PalFutexWait(addr: Pointer; expected: Integer): Integer;

{ Wake up to count waiters blocked on addr (FUTEX_WAKE). count = high value wakes
  all. Returns the number woken (raw syscall result). }
function PalFutexWake(addr: Pointer; count: Integer): Integer;

{ PalFutexWait bounded by a RELATIVE timeout in nanoseconds (ns < 0 = wait
  unbounded). Returns the raw syscall result: 0 woken, -ETIMEDOUT (-110) on
  expiry, -EAGAIN when addr^ <> expected. Backs pthread_cond_timedwait. }
function PalFutexWaitTimeout(addr: Pointer; expected: Integer; ns: Int64): Integer;

implementation

const
  FUTEX_WAIT = 0;
  FUTEX_WAKE = 1;

{$ifdef CPU_WASM32}

{ NO SYSCALL IS EMITTED HERE. See the note above: a runtime -1 in front of an
  emitted instruction is a refused body on this target, not a soft failure. }
function PalFutexWait(addr: Pointer; expected: Integer): Integer;
begin
  Result := -38;                  { -ENOSYS }
end;

function PalFutexWaitTimeout(addr: Pointer; expected: Integer; ns: Int64): Integer;
begin
  Result := -38;
end;

function PalFutexWake(addr: Pointer; count: Integer): Integer;
begin
  Result := -38;
end;

{$else}

{$ifdef CPUX86_64}
  SYS_futex = 202;
{$else}
{$ifdef CPUI386}
  SYS_futex = 240;                { i386 int 0x80 }
{$else}
{$ifdef CPUAARCH64}
  SYS_futex = 98;                 { asm-generic syscall table }
{$else}
{$ifdef CPUARM}
  SYS_futex = 240;                { arm32 EABI — same number as i386 here }
{$else}
{$ifdef CPU_RISCV32}
  SYS_futex = 422;                { futex_time64; rv32 has no plain futex at all }
{$else}
{$ifdef CPU_XTENSA}
  SYS_futex = 191;                { xtensa's own numbering, measured under qemu }
{$else}
  SYS_futex = -1;                 { no table for this target: fails at runtime }
{$endif}
{$endif}
{$endif}
{$endif}
{$endif}
{$endif}

function PalFutexWait(addr: Pointer; expected: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAIT, expected, 0, 0, 0));
end;

function PalFutexWaitTimeout(addr: Pointer; expected: Integer; ns: Int64): Integer;
{$ifdef CPU_RISCV32}
var
  ts: array[0..1] of Int64;       { futex_time64 takes a 64-BIT timespec, and
                                    NativeInt is 4 bytes here -- see the header }
{$else}
var
  ts: array[0..1] of NativeInt;   { struct timespec: tv_sec then tv_nsec, word-wide }
{$endif}
begin
  if ns < 0 then
  begin
    Result := PalFutexWait(addr, expected);
    Exit;
  end;
  ts[0] := ns div 1000000000;
  ts[1] := ns mod 1000000000;
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAIT, expected, Int64(@ts[0]), 0, 0));
end;

function PalFutexWake(addr: Pointer; count: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAKE, count, 0, 0, 0));
end;

{$endif}

end.
