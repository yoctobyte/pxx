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

  Linux only. Targets without a syscall table below get SYS_futex = -1, so the
  calls fail at runtime rather than failing the compile — the same shape the
  other PAL units use, and it keeps a unit that merely *mentions* a futex from
  breaking a build for a target that never blocks. }

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
  SYS_futex = -1;                 { no table for this target: fails at runtime }
{$endif}
{$endif}
{$endif}
{$endif}

function PalFutexWait(addr: Pointer; expected: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAIT, expected, 0, 0, 0));
end;

function PalFutexWaitTimeout(addr: Pointer; expected: Integer; ns: Int64): Integer;
var
  ts: array[0..1] of NativeInt;   { struct timespec: tv_sec then tv_nsec, word-wide }
begin
  if ns < 0 then
  begin
    Result := PalFutexWait(addr, expected);
    Exit;
  end;
  ts[0] := NativeInt(ns div 1000000000);
  ts[1] := NativeInt(ns mod 1000000000);
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAIT, expected, Int64(@ts[0]), 0, 0));
end;

function PalFutexWake(addr: Pointer; count: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_futex, Int64(addr), FUTEX_WAKE, count, 0, 0, 0));
end;

end.
