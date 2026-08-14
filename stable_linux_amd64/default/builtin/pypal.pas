{ SPDX-License-Identifier: Zlib }
unit pypal;

{ NilPy's Platform Abstraction Layer — the ONE place a NilPy runtime primitive
  reaches the kernel.

  Why a PAL per language rather than one shared layer: see
  devdocs/progress/backlog/decide-runtime-primitive-layering.md. Duplication
  between this unit, Pascal's lib/rtl/platform.pas and C's lib/rtl/pxxcio.pas is
  ACCEPTED and intentional — it is what stops a NilPy program linking sysutils
  to get one function. What is not accepted is what this unit replaces: 32 raw
  __pxxrawsyscall sites scattered through pylib.pas, each carrying its own copy
  of the per-arch number table.

  Those copies had drifted, which is the argument for the unit in one line:

    pyfile_slurp / pyos_remove / pyos_rename   5 arches (a local `nr*` table)
    pyos_getcwd / pyos_path_exists             5 arches (inline ifdefs)
    PyEnvLoad                                  2 arches (x86-64, aarch64)
    TPyFile.read/write/seek/tell/truncate/close  x86-64 ONLY — no ifdefs at all

  So `open()` was written five different ways and `os.environ` was silently
  empty on three targets pyfile_slurp handled fine. The numbers below are NOT
  invented: each is the one already used by whichever sibling in pylib.pas had
  the widest coverage.

  ADDING A TARGET = extending the table below and nothing else. That is the
  whole point of the unit; keep it that way.

  NOTE these are LINUX syscall numbers, and the openat/unlinkat/renameat/faccessat
  forms assume the Linux dirfd convention (AT_FDCWD = -100). A non-Linux target
  needs a different backend here, not more numbers — see the capability-vs-
  mechanism note in the decide- ticket. }

interface

const
  PYPAL_AT_FDCWD = -100;

  { O_* flags (Linux, arch-independent for the ones we use) }
  PYPAL_O_RDONLY = 0;
  PYPAL_O_WRONLY = 1;
  PYPAL_O_RDWR   = 2;
  PYPAL_O_CREAT  = 64;
  PYPAL_O_TRUNC  = 512;
  PYPAL_O_APPEND = 1024;

{ False on a target with no syscall table below — every entry point then fails
  softly (negative / empty) rather than issuing syscall 0. }
function PyPalSupported: Boolean;

function PyPalOpen(path: Pointer; flags, mode: Int64): Int64;
function PyPalRead(fd: Int64; buf: Pointer; n: Int64): Int64;
function PyPalWrite(fd: Int64; buf: Pointer; n: Int64): Int64;
function PyPalClose(fd: Int64): Int64;
function PyPalLseek(fd, offset, whence: Int64): Int64;
function PyPalFtruncate(fd, size: Int64): Int64;
function PyPalUnlink(path: Pointer): Int64;
function PyPalRename(src, dst: Pointer): Int64;
function PyPalGetcwd(buf: Pointer; n: Int64): Int64;
function PyPalStat(path, statbuf: Pointer): Int64;
function PyPalAccessOk(path: Pointer): Boolean;
{ ppoll(fds, nfds, timespec|nil, nil, 0) on ONE descriptor. Returns 1 when the
  requested events are ready, 0 on timeout, <0 on error / unsupported target.
  `ppoll` rather than `poll`: aarch64 and riscv32 have no plain poll(2) at all,
  and ppoll exists everywhere here, so one number per target covers the set.
  timeoutMs < 0 blocks (nil timespec), exactly like poll(2). }
function PyPalPoll(fd: Int64; events: Int64; timeoutMs: Int64): Int64;
{ readlink(2) via readlinkat, for resolving /proc/self/exe — how a program finds
  its OWN path. argv[0] is not that: it is whatever the exec caller passed, a
  PATH lookup or a relative path. Returns the byte count, or negative.
  NOT null-terminated by the kernel; the caller sets the length from the
  result. }
function PyPalReadlink(path: Pointer; buf: Pointer; bufsz: Int64): Int64;

implementation

{ ===== the per-arch syscall table — the only place numbers appear ============

  -1 marks "this target has no such call", and PYPAL_HAVE marks "this target has
  a table at all". NOT 0: on x86-64 `read` IS syscall 0, so a 0 sentinel makes
  the most common call on the most common target look unsupported. (It did —
  every file open and os.environ lookup failed softly while getcwd and
  path.exists worked, because only those two avoided the guard.) }

const
{$ifdef CPUX86_64}
  NR_OPEN_AT   = 257;   { openat }
  NR_READ      = 0;     { NB: read really IS 0 here — see the -1 note above }
  NR_WRITE     = 1;
  NR_CLOSE     = 3;
  NR_LSEEK     = 8;
  NR_FTRUNCATE = 77;
  NR_UNLINKAT  = 263;
  NR_RENAMEAT  = 264;
  NR_GETCWD    = 79;
  NR_STAT      = 4;     { stat (x86-64 has the plain form) }
  NR_ACCESS    = 21;    { access }
  NR_FACCESSAT = -1;     { not needed: plain access exists }
  NR_PPOLL     = 271;
  NR_READLINKAT= 267;
  PYPAL_HAVE   = True;
{$endif}
{$ifdef CPUAARCH64}
  NR_OPEN_AT   = 56;
  NR_READ      = 63;
  NR_WRITE     = 64;
  NR_CLOSE     = 57;
  NR_LSEEK     = 62;
  NR_FTRUNCATE = 46;
  NR_UNLINKAT  = 35;
  NR_RENAMEAT  = 38;
  NR_GETCWD    = 17;
  NR_STAT      = -1;     { no plain stat; fstatat only }
  NR_ACCESS    = -1;     { no plain access }
  NR_FACCESSAT = 48;
  NR_PPOLL     = 73;
  NR_READLINKAT= 78;
  PYPAL_HAVE   = True;
{$endif}
{$ifdef CPU_I386}
  NR_OPEN_AT   = 295;
  NR_READ      = 3;
  NR_WRITE     = 4;
  NR_CLOSE     = 6;
  NR_LSEEK     = 19;
  NR_FTRUNCATE = 93;
  NR_UNLINKAT  = 301;
  NR_RENAMEAT  = 302;
  NR_GETCWD    = 183;
  NR_STAT      = -1;
  NR_ACCESS    = 33;
  NR_FACCESSAT = -1;
  NR_PPOLL     = 309;
  NR_READLINKAT= 305;
  PYPAL_HAVE   = True;
{$endif}
{$ifdef CPU_ARM32}
  NR_OPEN_AT   = 322;
  NR_READ      = 3;
  NR_WRITE     = 4;
  NR_CLOSE     = 6;
  NR_LSEEK     = 19;
  NR_FTRUNCATE = 93;
  NR_UNLINKAT  = 328;
  NR_RENAMEAT  = 329;
  NR_GETCWD    = 183;
  NR_STAT      = -1;
  NR_ACCESS    = 33;
  NR_FACCESSAT = -1;
  NR_PPOLL     = 336;
  NR_READLINKAT= 332;
  PYPAL_HAVE   = True;
{$endif}
{ no table for this target — every entry point fails softly }
{$ifndef CPUX86_64}{$ifndef CPUAARCH64}{$ifndef CPU_I386}{$ifndef CPU_ARM32}{$ifndef CPU_RISCV32}
  NR_OPEN_AT   = -1;
  NR_READ      = -1;
  NR_WRITE     = -1;
  NR_CLOSE     = -1;
  NR_LSEEK     = -1;
  NR_FTRUNCATE = -1;
  NR_UNLINKAT  = -1;
  NR_RENAMEAT  = -1;
  NR_GETCWD    = -1;
  NR_STAT      = -1;
  NR_ACCESS    = -1;
  NR_FACCESSAT = -1;
  NR_PPOLL     = -1;
  NR_READLINKAT= -1;
  PYPAL_HAVE   = False;
{$endif}{$endif}{$endif}{$endif}{$endif}

{$ifdef CPU_RISCV32}
  NR_OPEN_AT   = 56;
  NR_READ      = 63;
  NR_WRITE     = 64;
  NR_CLOSE     = 57;
  NR_LSEEK     = 62;
  NR_FTRUNCATE = 46;
  NR_UNLINKAT  = 35;
  NR_RENAMEAT  = 38;
  NR_GETCWD    = 17;
  NR_STAT      = -1;
  NR_ACCESS    = -1;
  NR_FACCESSAT = 48;
  NR_PPOLL     = 73;
  NR_READLINKAT= 78;
  PYPAL_HAVE   = True;
{$endif}

function PyPalSupported: Boolean;
begin
  PyPalSupported := PYPAL_HAVE;
end;

type
  TPyPalPollFd = record
    fd:      LongInt;
    events:  SmallInt;
    revents: SmallInt;
  end;
  TPyPalTimespec = record
    tv_sec:  Int64;
    tv_nsec: Int64;
  end;

function PyPalPoll(fd: Int64; events: Int64; timeoutMs: Int64): Int64;
var pfd: TPyPalPollFd; ts: TPyPalTimespec; tsp: Pointer; r: Int64;
begin
  PyPalPoll := -1;
  if NR_PPOLL < 0 then Exit;
  pfd.fd := LongInt(fd);
  pfd.events := SmallInt(events);
  pfd.revents := 0;
  if timeoutMs < 0 then tsp := nil
  else
  begin
    ts.tv_sec := timeoutMs div 1000;
    ts.tv_nsec := (timeoutMs mod 1000) * 1000000;
    tsp := @ts;
  end;
  { arg 5 is the sigsetsize the kernel insists on when the mask (arg 4) is nil }
  r := __pxxrawsyscall(NR_PPOLL, Int64(@pfd), 1, Int64(tsp), 0, 8, 0);
  if r < 0 then begin PyPalPoll := r; Exit; end;
  if r = 0 then begin PyPalPoll := 0; Exit; end;
  if (pfd.revents and SmallInt(events)) <> 0 then PyPalPoll := 1
  else PyPalPoll := 0;
end;

{ openat(AT_FDCWD, path, flags, mode) — the portable form. x86-64's plain
  open(2) was what TPyFile used; openat is what every other target has, and it
  behaves identically for an absolute or CWD-relative path. }
function PyPalOpen(path: Pointer; flags, mode: Int64): Int64;
begin
  PyPalOpen := -1;
  if NR_OPEN_AT < 0 then Exit;
  PyPalOpen := __pxxrawsyscall(NR_OPEN_AT, PYPAL_AT_FDCWD, Int64(path), flags, mode, 0, 0);
end;

function PyPalRead(fd: Int64; buf: Pointer; n: Int64): Int64;
begin
  PyPalRead := -1;
  if NR_READ < 0 then Exit;
  PyPalRead := __pxxrawsyscall(NR_READ, fd, Int64(buf), n, 0, 0, 0);
end;

function PyPalWrite(fd: Int64; buf: Pointer; n: Int64): Int64;
begin
  PyPalWrite := -1;
  if NR_WRITE < 0 then Exit;
  PyPalWrite := __pxxrawsyscall(NR_WRITE, fd, Int64(buf), n, 0, 0, 0);
end;

function PyPalClose(fd: Int64): Int64;
begin
  PyPalClose := -1;
  if NR_CLOSE < 0 then Exit;
  PyPalClose := __pxxrawsyscall(NR_CLOSE, fd, 0, 0, 0, 0, 0);
end;

function PyPalLseek(fd, offset, whence: Int64): Int64;
begin
  PyPalLseek := -1;
  if NR_LSEEK < 0 then Exit;
  PyPalLseek := __pxxrawsyscall(NR_LSEEK, fd, offset, whence, 0, 0, 0);
end;

function PyPalFtruncate(fd, size: Int64): Int64;
begin
  PyPalFtruncate := -1;
  if NR_FTRUNCATE < 0 then Exit;
  PyPalFtruncate := __pxxrawsyscall(NR_FTRUNCATE, fd, size, 0, 0, 0, 0);
end;

function PyPalUnlink(path: Pointer): Int64;
begin
  PyPalUnlink := -1;
  if NR_UNLINKAT < 0 then Exit;
  PyPalUnlink := __pxxrawsyscall(NR_UNLINKAT, PYPAL_AT_FDCWD, Int64(path), 0, 0, 0, 0);
end;

function PyPalRename(src, dst: Pointer): Int64;
begin
  PyPalRename := -1;
  if NR_RENAMEAT < 0 then Exit;
  PyPalRename := __pxxrawsyscall(NR_RENAMEAT, PYPAL_AT_FDCWD, Int64(src),
                                 PYPAL_AT_FDCWD, Int64(dst), 0, 0);
end;

function PyPalReadlink(path: Pointer; buf: Pointer; bufsz: Int64): Int64;
begin
  PyPalReadlink := -1;
  if NR_READLINKAT < 0 then Exit;
  PyPalReadlink := __pxxrawsyscall(NR_READLINKAT, PYPAL_AT_FDCWD, Int64(path),
                                   Int64(buf), bufsz, 0, 0);
end;

function PyPalGetcwd(buf: Pointer; n: Int64): Int64;
begin
  PyPalGetcwd := -1;
  if NR_GETCWD < 0 then Exit;
  PyPalGetcwd := __pxxrawsyscall(NR_GETCWD, Int64(buf), n, 0, 0, 0, 0);
end;

function PyPalStat(path, statbuf: Pointer): Int64;
begin
  PyPalStat := -1;
  if NR_STAT < 0 then Exit;
  PyPalStat := __pxxrawsyscall(NR_STAT, Int64(path), Int64(statbuf), 0, 0, 0, 0);
end;

{ "does this path exist" — access(F_OK) where the target has it, faccessat
  otherwise. Kept as a BOOLEAN rather than exposing both syscalls, because the
  two forms take different arguments and every caller wants the same question. }
function PyPalAccessOk(path: Pointer): Boolean;
var r: Int64;
begin
  r := -1;
  if NR_ACCESS >= 0 then
    r := __pxxrawsyscall(NR_ACCESS, Int64(path), 0, 0, 0, 0, 0)
  else if NR_FACCESSAT >= 0 then
    r := __pxxrawsyscall(NR_FACCESSAT, PYPAL_AT_FDCWD, Int64(path), 0, 0, 0, 0);
  PyPalAccessOk := r = 0;
end;

end.
