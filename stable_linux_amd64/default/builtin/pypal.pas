{ SPDX-License-Identifier: Zlib }
unit pypal;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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
  { unlinkat's flag that makes it rmdir(2). Linux has no separate rmdir on the
    at-family path, so this reuses NR_UNLINKAT rather than adding a syscall
    number to all six tables. }
  PYPAL_AT_REMOVEDIR = 512;

  { ioctl(fd, TCGETS, &termios) -- what isatty(3) is. Arch-independent for
    every target here: asm-generic/ioctls.h gives 0x5401 and only mips, alpha,
    powerpc and sparc differ, none of which pxx targets. }
  TCGETS = $5401;

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
function PyPalRmdir(path: Pointer): Int64;
function PyPalRename(src, dst: Pointer): Int64;
function PyPalMkdir(path: Pointer; mode: Int64): Int64;
function PyPalGetcwd(buf: Pointer; n: Int64): Int64;
function PyPalStat(path, statbuf: Pointer): Int64;
function PyPalAccessOk(path: Pointer): Boolean;
{ isatty(3) is ioctl(fd, TCGETS, &termios) and nothing else -- 0 on a terminal,
  -ENOTTY otherwise -- which is exactly what glibc does. A BOOLEAN, because the
  only question anyone asks is the one CPython's sys.stdout.isatty() answers,
  and returning the raw ioctl status would make a caller test the wrong sign.
  TCGETS is 0x5401 on every target here (asm-generic/ioctls.h); the ones where
  it differs -- mips, alpha, powerpc, sparc -- are not targets. }
function PyPalIsatty(fd: Int64): Boolean;
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

{ CLOCK_REALTIME seconds+nanoseconds. False when this target has no number, so
  the caller raises rather than reporting the epoch. }
function PyPalClockRealtime(var sec: Int64; var nsec: Int64): Boolean;

{ One getdents64 fill. Returns bytes written to buf, 0 at end of directory,
  negative on error (including -1 for "no number on this target"). }
function PyPalGetdents(fd: Int64; buf: Pointer; n: Int64): Int64;

{ Whether this target HAS a getdents64 number, asked separately because the
  error return cannot carry it: -1 is also EPERM, so a caller that only saw the
  return value would report a permission problem on a target that simply has no
  entry in the table. arm32 is that target today. }
function PyPalHasGetdents: Boolean;

{ st_mode and st_size of `path`, portably: 0, or -errno, or -38 (ENOSYS)
  where this unit knows no stat layout for the target. pylib asks THIS rather
  than decoding a struct stat itself, so a new target is one arm here. }
function PyPalStatModeSize(path: Pointer; var mode: Int64; var size: Int64): Int64;

{ NEWLIB'S ERRNO, IN LINUX NUMBERING -- the one copy of this table (the PAL
  contract everywhere is -errno in Linux's numbering, and newlib's differs for
  69 names: ETIMEDOUT is 116 there, 110 on Linux). GENERATED, not recalled: the
  ESP toolchain's sys/errno.h (xtensa and riscv32 identical) joined by NAME with
  CPython's errno module, listing only the names whose numbers differ; the
  other 50 pass through. lib/rtl/platform/esp/platform_backend.pas still
  carries a copy until a pin carries this function -- then it uses this one. }
function PyPalLinuxErrno(newlibErrno: Integer): Integer;

implementation

function PyPalLinuxErrno(newlibErrno: Integer): Integer;
begin
  case newlibErrno of
    35: PyPalLinuxErrno := 42;   { ENOMSG }
    36: PyPalLinuxErrno := 43;   { EIDRM }
    37: PyPalLinuxErrno := 44;   { ECHRNG }
    38: PyPalLinuxErrno := 45;   { EL2NSYNC }
    39: PyPalLinuxErrno := 46;   { EL3HLT }
    40: PyPalLinuxErrno := 47;   { EL3RST }
    41: PyPalLinuxErrno := 48;   { ELNRNG }
    42: PyPalLinuxErrno := 49;   { EUNATCH }
    43: PyPalLinuxErrno := 50;   { ENOCSI }
    44: PyPalLinuxErrno := 51;   { EL2HLT }
    45: PyPalLinuxErrno := 35;   { EDEADLK }
    46: PyPalLinuxErrno := 37;   { ENOLCK }
    50: PyPalLinuxErrno := 52;   { EBADE }
    51: PyPalLinuxErrno := 53;   { EBADR }
    52: PyPalLinuxErrno := 54;   { EXFULL }
    53: PyPalLinuxErrno := 55;   { ENOANO }
    54: PyPalLinuxErrno := 56;   { EBADRQC }
    55: PyPalLinuxErrno := 57;   { EBADSLT }
    56: PyPalLinuxErrno := 35;   { EDEADLOCK }
    57: PyPalLinuxErrno := 59;   { EBFONT }
    74: PyPalLinuxErrno := 72;   { EMULTIHOP }
    76: PyPalLinuxErrno := 73;   { EDOTDOT }
    77: PyPalLinuxErrno := 74;   { EBADMSG }
    80: PyPalLinuxErrno := 76;   { ENOTUNIQ }
    81: PyPalLinuxErrno := 77;   { EBADFD }
    82: PyPalLinuxErrno := 78;   { EREMCHG }
    83: PyPalLinuxErrno := 79;   { ELIBACC }
    84: PyPalLinuxErrno := 80;   { ELIBBAD }
    85: PyPalLinuxErrno := 81;   { ELIBSCN }
    86: PyPalLinuxErrno := 82;   { ELIBMAX }
    87: PyPalLinuxErrno := 83;   { ELIBEXEC }
    88: PyPalLinuxErrno := 38;   { ENOSYS }
    90: PyPalLinuxErrno := 39;   { ENOTEMPTY }
    91: PyPalLinuxErrno := 36;   { ENAMETOOLONG }
    92: PyPalLinuxErrno := 40;   { ELOOP }
    106: PyPalLinuxErrno := 97;   { EAFNOSUPPORT }
    107: PyPalLinuxErrno := 91;   { EPROTOTYPE }
    108: PyPalLinuxErrno := 88;   { ENOTSOCK }
    109: PyPalLinuxErrno := 92;   { ENOPROTOOPT }
    110: PyPalLinuxErrno := 108;   { ESHUTDOWN }
    112: PyPalLinuxErrno := 98;   { EADDRINUSE }
    113: PyPalLinuxErrno := 103;   { ECONNABORTED }
    114: PyPalLinuxErrno := 101;   { ENETUNREACH }
    115: PyPalLinuxErrno := 100;   { ENETDOWN }
    116: PyPalLinuxErrno := 110;   { ETIMEDOUT }
    117: PyPalLinuxErrno := 112;   { EHOSTDOWN }
    118: PyPalLinuxErrno := 113;   { EHOSTUNREACH }
    119: PyPalLinuxErrno := 115;   { EINPROGRESS }
    120: PyPalLinuxErrno := 114;   { EALREADY }
    121: PyPalLinuxErrno := 89;   { EDESTADDRREQ }
    122: PyPalLinuxErrno := 90;   { EMSGSIZE }
    123: PyPalLinuxErrno := 93;   { EPROTONOSUPPORT }
    124: PyPalLinuxErrno := 94;   { ESOCKTNOSUPPORT }
    125: PyPalLinuxErrno := 99;   { EADDRNOTAVAIL }
    126: PyPalLinuxErrno := 102;   { ENETRESET }
    127: PyPalLinuxErrno := 106;   { EISCONN }
    128: PyPalLinuxErrno := 107;   { ENOTCONN }
    129: PyPalLinuxErrno := 109;   { ETOOMANYREFS }
    131: PyPalLinuxErrno := 87;   { EUSERS }
    132: PyPalLinuxErrno := 122;   { EDQUOT }
    133: PyPalLinuxErrno := 116;   { ESTALE }
    134: PyPalLinuxErrno := 95;   { ENOTSUP }
    135: PyPalLinuxErrno := 123;   { ENOMEDIUM }
    138: PyPalLinuxErrno := 84;   { EILSEQ }
    139: PyPalLinuxErrno := 75;   { EOVERFLOW }
    140: PyPalLinuxErrno := 125;   { ECANCELED }
    141: PyPalLinuxErrno := 131;   { ENOTRECOVERABLE }
    142: PyPalLinuxErrno := 130;   { EOWNERDEAD }
    143: PyPalLinuxErrno := 86;   { ESTRPIPE }
  else
    PyPalLinuxErrno := newlibErrno;
  end;
end;

{ ===== ESP-IDF: files through IDF's VFS, not through a kernel ===============

  There is no kernel under FreeRTOS, so this profile answers every entry point
  from newlib's POSIX layer (open/read/write/... resolved by the IDF link),
  which IDF routes through its VFS. Before this arm, xtensa had no table and
  riscv32's syscalls were answered -ENOSYS by the codegen, so NO file call had
  ever worked on an ESP: open() raised "[Errno 1]" for every path.

  THE FILESYSTEM is FAT-on-flash with wear levelling, mounted at IDF prefix
  /fs by the pxx_esp component (lib/rtl/platform/esp/idf/pxx_esp/pxx_fs.c)
  when the partition table has a `storage` FAT partition. Python never sees
  that prefix: as on MicroPython, "/" is the filesystem's root and a relative
  path is relative to it (there is no chdir). A project without the component
  or the partition has no /fs, and every path answers ENOENT -- a refusal,
  not a fake.

  Flags and errno are newlib's on this side, so both are TRANSLATED here, and
  the stat/dirent offsets are newlib's for these chips -- measured with the
  xtensa and riscv32 toolchains (identical): st_mode @4 and st_size @16, four
  bytes each, struct stat 88 bytes; dirent d_name @3; O_CREAT $200, O_TRUNC
  $400, O_APPEND $8, O_EXCL $800. }
{$ifdef PXX_ESP_IDF}
function EspOpen(path: PChar; flags, mode: Integer): Integer; cdecl; external name 'open';
function EspRead(fd: Integer; buf: Pointer; n: Integer): Integer; cdecl; external name 'read';
function EspWrite(fd: Integer; buf: Pointer; n: Integer): Integer; cdecl; external name 'write';
function EspClose(fd: Integer): Integer; cdecl; external name 'close';
function EspLseek(fd, offset, whence: Integer): Integer; cdecl; external name 'lseek';
function EspFtruncate(fd, len: Integer): Integer; cdecl; external name 'ftruncate';
function EspUnlink(path: PChar): Integer; cdecl; external name 'unlink';
function EspRmdir(path: PChar): Integer; cdecl; external name 'rmdir';
function EspRename(src, dst: PChar): Integer; cdecl; external name 'rename';
function EspMkdir(path: PChar; mode: Integer): Integer; cdecl; external name 'mkdir';
function EspStat(path: PChar; buf: Pointer): Integer; cdecl; external name 'stat';
function EspOpendir(path: PChar): Pointer; cdecl; external name 'opendir';
function EspReaddir(d: Pointer): Pointer; cdecl; external name 'readdir';
function EspClosedir(d: Pointer): Integer; cdecl; external name 'closedir';
function EspErrnoPtr: PInteger; cdecl; external name '__errno';
function EspPutchar(c: Integer): Integer; cdecl; external name 'putchar';
{ The filesystem's mount, OPTIONAL: lib/rtl/platform/esp/idf/pxx_fs defines
  it, and a project that does not REQUIRE that component links with this nil
  and has no filesystem -- every path answers ENOENT. Called once, lazily, on
  the first path a program names, so it runs in a task and not at boot. }
function EspFsMount: Integer; cdecl; weakexternal name 'pxx_fs_mount';
function EspGetchar: Integer; cdecl; external name 'getchar';

const
  ESP_FS_PREFIX = '/fs';
  { a directory "fd": opendir's DIR* in a slot, numbered far above any VFS fd }
  ESP_DIRFD_BASE = $40000000;
  ESP_DIR_SLOTS = 8;

var
  EspDirs: array[0..ESP_DIR_SLOTS - 1] of Pointer;
  EspFsTried: Boolean;

{ -errno (Linux numbering) for a newlib call that just failed }
function EspFail: Int64;
var e: Integer;
begin
  e := EspErrnoPtr^;
  if e <= 0 then EspFail := -5          { EIO: failed with nothing recorded }
  else EspFail := -PyPalLinuxErrno(e);
end;

function EspRet(r: Integer): Int64;
begin
  if r < 0 then EspRet := EspFail else EspRet := r;
end;

{ Python's path -> IDF's: "/" is /fs, "x" and "./x" are /fs/x. }
function EspPath(path: Pointer): AnsiString;
var p: PChar; s: AnsiString;
begin
  if not EspFsTried then
  begin
    EspFsTried := True;
    if @EspFsMount <> nil then EspFsMount;
  end;
  p := PChar(path);
  s := '';
  while p^ <> #0 do begin s := s + p^; Inc(p); end;
  while (Length(s) >= 2) and (s[1] = '.') and (s[2] = '/') do Delete(s, 1, 2);
  if s = '.' then s := '';
  if (Length(s) > 0) and (s[1] = '/') then Delete(s, 1, 1);
  while (Length(s) > 0) and (s[Length(s)] = '/') do Delete(s, Length(s), 1);
  if s = '' then EspPath := ESP_FS_PREFIX + #0
  else EspPath := ESP_FS_PREFIX + '/' + s + #0;
end;

function EspDirSlot(fd: Int64): Integer;
begin
  EspDirSlot := -1;
  if (fd >= ESP_DIRFD_BASE) and (fd < ESP_DIRFD_BASE + ESP_DIR_SLOTS) then
    if EspDirs[fd - ESP_DIRFD_BASE] <> nil then
      EspDirSlot := fd - ESP_DIRFD_BASE;
end;

function EspFlags(flags: Int64): Integer;
var f: Integer;
begin
  f := flags and 3;                                      { O_ACCMODE, same value }
  if (flags and PYPAL_O_CREAT) <> 0 then f := f or $200;
  if (flags and PYPAL_O_TRUNC) <> 0 then f := f or $400;
  if (flags and PYPAL_O_APPEND) <> 0 then f := f or $8;
  if (flags and 128) <> 0 then f := f or $800;           { O_EXCL }
  EspFlags := f;
end;

function EspOpenPath(path: Pointer; flags, mode: Int64): Int64;
var p: AnsiString; d: Pointer; i: Integer;
begin
  p := EspPath(path);
  { a directory opens READ-ONLY as a listing handle -- which is what listdir
    wants, and what lets open() answer IsADirectoryError as on Linux }
  if (flags and 3) = PYPAL_O_RDONLY then
  begin
    d := EspOpendir(@p[1]);
    if d <> nil then
    begin
      for i := 0 to ESP_DIR_SLOTS - 1 do
        if EspDirs[i] = nil then
        begin
          EspDirs[i] := d;
          EspOpenPath := ESP_DIRFD_BASE + i;
          Exit;
        end;
      EspClosedir(d);
      EspOpenPath := -24;                                { EMFILE }
      Exit;
    end;
  end;
  EspOpenPath := EspRet(EspOpen(@p[1], EspFlags(flags), Integer(mode)));
end;

{ linux_dirent64 records from readdir: d_ino @0, d_off @8, d_reclen @16,
  d_type @18, d_name @19, each 8-aligned -- the shape pylib's listdir walks. }
function EspGetdents(slot: Integer; buf: Pointer; n: Int64): Int64;
var ent: PByte; name: PChar; len, rec, pos, k: Integer; b: PByte;
begin
  b := PByte(buf);
  pos := 0;
  while True do
  begin
    ent := PByte(EspReaddir(EspDirs[slot]));
    if ent = nil then Break;
    name := PChar(ent + 3);
    len := 0;
    while name[len] <> #0 do Inc(len);
    rec := (19 + len + 1 + 7) and not 7;
    if pos + rec > n then Break;   { the next call cannot rewind; the buffer is 8 KB, a FAT name at most 255 }
    for k := 0 to rec - 1 do b[pos + k] := 0;
    b[pos + 16] := rec and 255;
    b[pos + 17] := (rec shr 8) and 255;
    for k := 0 to len - 1 do b[pos + 19 + k] := Byte(name[k]);
    pos := pos + rec;
  end;
  EspGetdents := pos;
end;
{$endif}

{ ===== the per-arch syscall table — the only place numbers appear ============

  -1 marks "this target has no such call", and PYPAL_HAVE marks "this target has
  a table at all". NOT 0: on x86-64 `read` IS syscall 0, so a 0 sentinel makes
  the most common call on the most common target look unsupported. (It did —
  every file open and os.environ lookup failed softly while getcwd and
  path.exists worked, because only those two avoided the guard.) }

{ NR_CLOCK_GETTIME and NR_GETDENTS64 (added 2026-08-29) — read one arch at a
  time out of this machine's kernel headers, never derived from a sibling.
  Deriving is the specific trap here: i386 and arm32 sit +27 apart for
  openat/unlinkat/renameat/ppoll/readlinkat in the table above, and that offset
  does NOT extend to getdents64 (i386 220, arm32 217). One arch's number is
  evidence about that arch only.

  CLOCK: the 64-bit targets use clock_gettime; the 32-bit ones use
  clock_gettime64 (403), NOT the legacy 32-bit clock_gettime. Two reasons, and
  the first is correctness rather than taste:
    * riscv32 does not HAVE the legacy one. asm-generic/unistd.h gates
      __NR_clock_gettime 113 on `__ARCH_WANT_TIME32_SYSCALLS || __BITS_PER_LONG
      != 32`, and riscv32 (time64-only from the start) defines neither.
    * it makes the struct UNIFORM. clock_gettime64 takes a __kernel_timespec —
      two 64-bit fields — which is byte-identical to the 64-bit targets'
      struct timespec, so TPyPalTimespec is one layout on every target rather
      than a per-arch record. It is also y2038-clean by construction.
  The time64 block (403..414) was deliberately assigned the SAME numbers on
  every 32-bit ABI, which is why 403 is right for i386, arm32 and riscv32
  alike; confirmed here against both i386's own header and the kernel's generic
  syscall.tbl (`403 32 clock_gettime64`).

  PPOLL IS THE SAME ARGUMENT AND WAS LEFT OUT OF IT FOR A WEEK (fixed
  2026-09-06). NR_PPOLL used to be the LEGACY number on the 32-bit targets —
  i386 309, arm32 336, riscv32 73 — and the legacy ppoll takes a 32-bit
  timespec while TPyPalTimespec is two Int64. So the kernel read tv_sec from
  the low half of our first field and tv_nsec from its HIGH half, which is
  always zero: every sub-second timeout became a poll that returned
  immediately, and riscv32 (which has no legacy ppoll at all) answered ENOSYS.
  ppoll_time64 is 414 on all three, takes the __kernel_timespec we already
  build, and needs no second record. One struct, one number, three targets —
  which is what the clock entry above bought and this one now does too. 

  VERIFIED HOW, name by name — this is the part a reader needs, because a wrong
  number is invisible on five of six targets and issues an UNRELATED syscall:
    x86-64   header  /usr/include/x86_64-linux-gnu/asm/unistd_64.h  (228, 217)
    i386     header  .../asm/unistd_32.h  (clock_gettime64 403, getdents64 220)
    aarch64  header  /usr/include/asm-generic/unistd.h  (113, 61)
    riscv32  header  same, 32-bit arm of the gate above  (403, 61)
    arm32    clock_gettime64 403 — from the uniform time64 block, cross-checked
             against two independent sources above.
    arm32    getdents64 217 — filled 2026-09-06. It was -1 for a week because
             the machine that added os.listdir had no arm/syscall.tbl and
             would not derive a number from a sibling, which was the right
             call: the i386/arm32 +27 offset that holds for openat, unlinkat,
             renameat, ppoll and readlinkat does NOT hold here (i386 220,
             arm32 217), and the derived 247 is another syscall entirely.
             Three instruments now agree and they fail differently:
             tools/syscall-maps/arm32.txt (a qemu -strace SWEEP, not a
             header read) has `217 getdents64'; the original ticket's own text
             cites 217 while arguing the offset does not extend; and
             os.listdir was run end to end under qemu-arm and returned the
             right names. A wrong number here does not fail — it issues an
             unrelated syscall — so the end-to-end run is the one that counts.
             getdents64 = -1, DELIBERATELY. This machine carries no arm32
             syscall table (arch/arm/tools/syscall.tbl is absent from the
             installed headers) and the number cannot be derived from i386.
             -1 is this table's own "no such call" sentinel, so os.listdir
             fails softly on arm32 instead of issuing whatever 217 happens to
             mean there. Fill it in from an arm32 header, not from memory:
             bug-n-pypal-arm32-getdents64-is-unfilled }

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
  NR_MKDIRAT   = 258;
  NR_IOCTL     = 16;
  NR_GETCWD    = 79;
  NR_STAT      = 4;     { stat (x86-64 has the plain form) }
  NR_ACCESS    = 21;    { access }
  NR_FACCESSAT = -1;     { not needed: plain access exists }
  NR_PPOLL     = 271;
  NR_READLINKAT= 267;
  NR_CLOCK_GETTIME = 228;
  NR_GETDENTS64 = 217;
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
  NR_MKDIRAT   = 34;
  NR_IOCTL     = 29;
  NR_GETCWD    = 17;
  NR_STAT      = -1;     { no plain stat; fstatat only }
  NR_ACCESS    = -1;     { no plain access }
  NR_FACCESSAT = 48;
  NR_PPOLL     = 73;
  NR_READLINKAT= 78;
  NR_CLOCK_GETTIME = 113;
  NR_GETDENTS64 = 61;
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
  NR_MKDIRAT   = 296;
  NR_IOCTL     = 54;
  NR_GETCWD    = 183;
  NR_STAT      = -1;
  NR_ACCESS    = 33;
  NR_FACCESSAT = -1;
  NR_PPOLL     = 414;   { ppoll_time64 — see the timespec note above }
  NR_READLINKAT= 305;
  NR_CLOCK_GETTIME = 403;
  NR_GETDENTS64 = 220;
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
  NR_MKDIRAT   = 323;
  NR_IOCTL     = 54;
  NR_GETCWD    = 183;
  NR_STAT      = -1;
  NR_ACCESS    = 33;
  NR_FACCESSAT = -1;
  NR_PPOLL     = 414;   { ppoll_time64 — see the timespec note above }
  NR_READLINKAT= 332;
  NR_CLOCK_GETTIME = 403;
  NR_GETDENTS64 = 217;
  PYPAL_HAVE   = True;
{$endif}
{ no table for this target — every entry point fails softly }
{$ifndef CPUX86_64}{$ifndef CPUAARCH64}{$ifndef CPU_I386}{$ifndef CPU_ARM32}{$ifndef CPU_RISCV32}
{ AND NO SYSCALL INSTRUCTION IS EMITTED AT ALL. `PYPAL_HAVE = False` makes every
  entry point fail softly at RUNTIME, and that was not enough: the
  __pxxrawsyscall call still sat in each body, so wasm32 -- which has no syscall
  numbers and cannot have them, since wasi has imports -- refused to lower the
  bodies and emitted fifteen of them as `unreachable`. A NilPy program then did
  not fail softly, it failed to COMPILE, and the refusal was correct about the
  instruction and wrong about the program: the body should never have been asked
  to issue a raw syscall on this target.

  Declared HERE, inside the very conditional that decides PYPAL_HAVE, so the two
  cannot drift. A separate list of targets would be a second name for one fact.
  bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32 }
{$define PYPAL_NO_SYSCALLS}
  NR_OPEN_AT   = -1;
  NR_READ      = -1;
  NR_WRITE     = -1;
  NR_CLOSE     = -1;
  NR_LSEEK     = -1;
  NR_FTRUNCATE = -1;
  NR_UNLINKAT  = -1;
  NR_RENAMEAT  = -1;
  NR_MKDIRAT   = -1;
  NR_IOCTL     = -1;
  NR_GETCWD    = -1;
  NR_STAT      = -1;
  NR_ACCESS    = -1;
  NR_FACCESSAT = -1;
  NR_PPOLL     = -1;
  NR_READLINKAT= -1;
  NR_CLOCK_GETTIME = -1;
  NR_GETDENTS64 = -1;
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
  NR_MKDIRAT   = 34;
  NR_IOCTL     = 29;
  NR_GETCWD    = 17;
  NR_STAT      = -1;
  NR_ACCESS    = -1;
  NR_FACCESSAT = 48;
  NR_PPOLL     = 414;   { ppoll_time64 — see the timespec note above }
  NR_READLINKAT= 78;
  NR_CLOCK_GETTIME = 403;
  NR_GETDENTS64 = 61;
  PYPAL_HAVE   = True;
{$endif}

function PyPalSupported: Boolean;
begin
{$ifdef PXX_ESP_IDF}
  PyPalSupported := True;   { through IDF's VFS -- see the ESP-IDF arm }
{$else}
  PyPalSupported := PYPAL_HAVE;
{$endif}
end;

{ THE ONE SYSCALL SITE IN THIS UNIT, and the reason it exists is a target that
  has no syscalls rather than a target that has different ones.

  Every body below used to spell `__pxxrawsyscall` itself. All seventeen calls
  had the identical shape -- a number and six Int64 arguments -- so the sites
  carried no information the funnel does not, while each was a separate place a
  backend without an IR_SYSCALL arm had to refuse. Fifteen refusals became one,
  and then none, because this body has no syscall in it on such a target.

  The unit header promises `ADDING A TARGET = extending the table and nothing
  else`. That promise is what this keeps: a new target with numbers gets a
  table block and reaches the kernel through here; a new target WITHOUT them
  gets nothing at all and every entry point returns the same -1 it already
  documented. }
function PyPalSys(nr, a1, a2, a3, a4, a5, a6: Int64): Int64;
begin
{$ifdef PYPAL_NO_SYSCALLS}
  { every caller already guards on `NR_xxx < 0`, which is -1 on this target, so
    this return is unreachable in practice and is the honest value if it is not }
  PyPalSys := -1;
{$else}
  PyPalSys := __pxxrawsyscall(nr, a1, a2, a3, a4, a5, a6);
{$endif}
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
  r := PyPalSys(NR_PPOLL, Int64(@pfd), 1, Int64(tsp), 0, 8, 0);
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
{$ifdef PXX_ESP_IDF}
  PyPalOpen := EspOpenPath(path, flags, mode);
  Exit;
{$endif}
  PyPalOpen := -1;
  if NR_OPEN_AT < 0 then Exit;
  PyPalOpen := PyPalSys(NR_OPEN_AT, PYPAL_AT_FDCWD, Int64(path), flags, mode, 0, 0);
end;

function PyPalRead(fd: Int64; buf: Pointer; n: Int64): Int64;
{$ifdef PXX_ESP_IDF}
var k: Integer;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  if EspDirSlot(fd) >= 0 then begin PyPalRead := -21; Exit; end;   { EISDIR }
  if fd = 0 then
  begin
    { the console is not a VFS fd under IDF (see builtinheap's
      PXXIdfStdWrite): a line at a time through getchar, as a tty read }
    PyPalRead := 0;
    while PyPalRead < n do
    begin
      k := EspGetchar;
      if k < 0 then Break;
      PByte(buf)[PyPalRead] := Byte(k);
      PyPalRead := PyPalRead + 1;
      if k = 10 then Break;
    end;
    Exit;
  end;
  PyPalRead := EspRet(EspRead(fd, buf, n));
  Exit;
{$endif}
  PyPalRead := -1;
  if NR_READ < 0 then Exit;
  PyPalRead := PyPalSys(NR_READ, fd, Int64(buf), n, 0, 0, 0);
end;

function PyPalWrite(fd: Int64; buf: Pointer; n: Int64): Int64;
{$ifdef PXX_ESP_IDF}
var k: Integer;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  if EspDirSlot(fd) >= 0 then begin PyPalWrite := -9; Exit; end;   { EBADF }
  if (fd = 1) or (fd = 2) then
  begin
    for k := 0 to n - 1 do
      if EspPutchar(PByte(buf)[k]) < 0 then begin PyPalWrite := -5; Exit; end;
    PyPalWrite := n;
    Exit;
  end;
  PyPalWrite := EspRet(EspWrite(fd, buf, n));
  Exit;
{$endif}
  PyPalWrite := -1;
  if NR_WRITE < 0 then Exit;
  PyPalWrite := PyPalSys(NR_WRITE, fd, Int64(buf), n, 0, 0, 0);
end;

function PyPalClose(fd: Int64): Int64;
{$ifdef PXX_ESP_IDF}
var k: Integer;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  k := EspDirSlot(fd);
  if k >= 0 then
  begin
    EspClosedir(EspDirs[k]);
    EspDirs[k] := nil;
    PyPalClose := 0;
    Exit;
  end;
  PyPalClose := EspRet(EspClose(fd));
  Exit;
{$endif}
  PyPalClose := -1;
  if NR_CLOSE < 0 then Exit;
  PyPalClose := PyPalSys(NR_CLOSE, fd, 0, 0, 0, 0, 0);
end;

function PyPalLseek(fd, offset, whence: Int64): Int64;
begin
{$ifdef PXX_ESP_IDF}
  PyPalLseek := EspRet(EspLseek(fd, offset, whence));
  Exit;
{$endif}
  PyPalLseek := -1;
  if NR_LSEEK < 0 then Exit;
  PyPalLseek := PyPalSys(NR_LSEEK, fd, offset, whence, 0, 0, 0);
end;

function PyPalFtruncate(fd, size: Int64): Int64;
begin
{$ifdef PXX_ESP_IDF}
  PyPalFtruncate := EspRet(EspFtruncate(fd, size));
  Exit;
{$endif}
  PyPalFtruncate := -1;
  if NR_FTRUNCATE < 0 then Exit;
  PyPalFtruncate := PyPalSys(NR_FTRUNCATE, fd, size, 0, 0, 0, 0);
end;

function PyPalUnlink(path: Pointer): Int64;
{$ifdef PXX_ESP_IDF}
var p: AnsiString;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  p := EspPath(path);
  PyPalUnlink := EspRet(EspUnlink(@p[1]));
  Exit;
{$endif}
  PyPalUnlink := -1;
  if NR_UNLINKAT < 0 then Exit;
  PyPalUnlink := PyPalSys(NR_UNLINKAT, PYPAL_AT_FDCWD, Int64(path), 0, 0, 0, 0);
end;

function PyPalRmdir(path: Pointer): Int64;
{$ifdef PXX_ESP_IDF}
var p: AnsiString;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  p := EspPath(path);
  PyPalRmdir := EspRet(EspRmdir(@p[1]));
  Exit;
{$endif}
  PyPalRmdir := -1;
  if NR_UNLINKAT < 0 then Exit;
  PyPalRmdir := PyPalSys(NR_UNLINKAT, PYPAL_AT_FDCWD, Int64(path),
                                 PYPAL_AT_REMOVEDIR, 0, 0, 0);
end;

function PyPalRename(src, dst: Pointer): Int64;
{$ifdef PXX_ESP_IDF}
var a, b: AnsiString;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  a := EspPath(src);
  b := EspPath(dst);
  PyPalRename := EspRet(EspRename(@a[1], @b[1]));
  Exit;
{$endif}
  PyPalRename := -1;
  if NR_RENAMEAT < 0 then Exit;
  PyPalRename := PyPalSys(NR_RENAMEAT, PYPAL_AT_FDCWD, Int64(src),
                                 PYPAL_AT_FDCWD, Int64(dst), 0, 0);
end;

function PyPalMkdir(path: Pointer; mode: Int64): Int64;
{$ifdef PXX_ESP_IDF}
var p: AnsiString;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  p := EspPath(path);
  PyPalMkdir := EspRet(EspMkdir(@p[1], mode));
  Exit;
{$endif}
  PyPalMkdir := -1;
  if NR_MKDIRAT < 0 then Exit;
  PyPalMkdir := PyPalSys(NR_MKDIRAT, PYPAL_AT_FDCWD, Int64(path), mode,
                                 0, 0, 0);
end;

function PyPalReadlink(path: Pointer; buf: Pointer; bufsz: Int64): Int64;
begin
  PyPalReadlink := -1;
  if NR_READLINKAT < 0 then Exit;
  PyPalReadlink := PyPalSys(NR_READLINKAT, PYPAL_AT_FDCWD, Int64(path),
                                   Int64(buf), bufsz, 0, 0);
end;

function PyPalGetcwd(buf: Pointer; n: Int64): Int64;
begin
{$ifdef PXX_ESP_IDF}
  { no chdir: the working directory is the root, always }
  if n < 2 then begin PyPalGetcwd := -34; Exit; end;   { ERANGE }
  PByte(buf)[0] := Ord('/');
  PByte(buf)[1] := 0;
  PyPalGetcwd := 2;
  Exit;
{$endif}
  PyPalGetcwd := -1;
  if NR_GETCWD < 0 then Exit;
  PyPalGetcwd := PyPalSys(NR_GETCWD, Int64(buf), n, 0, 0, 0, 0);
end;

function PyPalStat(path, statbuf: Pointer): Int64;
begin
  PyPalStat := -1;
  if NR_STAT < 0 then Exit;
  PyPalStat := PyPalSys(NR_STAT, Int64(path), Int64(statbuf), 0, 0, 0, 0);
end;

{ "does this path exist" — access(F_OK) where the target has it, faccessat
  otherwise. Kept as a BOOLEAN rather than exposing both syscalls, because the
  two forms take different arguments and every caller wants the same question. }
function PyPalAccessOk(path: Pointer): Boolean;
var r: Int64;
{$ifdef PXX_ESP_IDF}
    m, z: Int64;
{$endif}
begin
{$ifdef PXX_ESP_IDF}
  PyPalAccessOk := PyPalStatModeSize(path, m, z) = 0;
  Exit;
{$endif}
  r := -1;
  if NR_ACCESS >= 0 then
    r := PyPalSys(NR_ACCESS, Int64(path), 0, 0, 0, 0, 0)
  else if NR_FACCESSAT >= 0 then
    r := PyPalSys(NR_FACCESSAT, PYPAL_AT_FDCWD, Int64(path), 0, 0, 0, 0);
  PyPalAccessOk := r = 0;
end;

function PyPalIsatty(fd: Int64): Boolean;
var buf: array[0..63] of Byte;
begin
  { struct termios is 60 bytes on Linux (c_?flag x4, c_line, c_cc[19], then
    c_ispeed/c_ospeed); 64 is that rounded up. The CONTENTS are never read --
    only whether the call succeeded -- but the kernel writes the whole struct,
    so the buffer has to be big enough or ioctl scribbles past it. }
  PyPalIsatty := False;
  if NR_IOCTL < 0 then Exit;
  FillChar(buf[0], SizeOf(buf), 0);
  PyPalIsatty := PyPalSys(NR_IOCTL, fd, TCGETS, Int64(@buf[0]), 0, 0, 0) = 0;
end;

{ CLOCK_REALTIME, as seconds + nanoseconds. Boolean rather than an Int64 return
  because there is no in-band value for failure: 0 seconds is a legal (if
  absurd) answer, and a caller that reported the epoch on an unsupported target
  would be wrong QUIETLY -- which on a clock is the whole failure mode. On the
  32-bit targets NR_CLOCK_GETTIME is clock_gettime64, whose __kernel_timespec
  is two 64-bit fields, so TPyPalTimespec is the right shape everywhere. }
function PyPalClockRealtime(var sec: Int64; var nsec: Int64): Boolean;
var ts: TPyPalTimespec; r: Int64;
begin
  PyPalClockRealtime := False;
  sec := 0;
  nsec := 0;
  if NR_CLOCK_GETTIME < 0 then Exit;
  ts.tv_sec := 0;
  ts.tv_nsec := 0;
  { arg 1 is CLOCK_REALTIME (0) — the wall clock time.time() reports, not the
    monotonic one; they differ across a settimeofday and Python promises this. }
  r := PyPalSys(NR_CLOCK_GETTIME, 0, Int64(@ts), 0, 0, 0, 0);
  if r < 0 then Exit;
  sec := ts.tv_sec;
  nsec := ts.tv_nsec;
  PyPalClockRealtime := True;
end;

{ One getdents64 fill. The BUFFER WALK is the caller's job, not this unit's:
  the kernel packs variable-length records and decoding them is data handling,
  while this unit's whole contract is "reach the kernel and nothing else".
  Returns bytes written, 0 at end of directory, negative on error — and -1 on a
  target with no number, which arm32 currently is. }
function PyPalGetdents(fd: Int64; buf: Pointer; n: Int64): Int64;
begin
{$ifdef PXX_ESP_IDF}
  if EspDirSlot(fd) < 0 then begin PyPalGetdents := -20; Exit; end;   { ENOTDIR }
  PyPalGetdents := EspGetdents(EspDirSlot(fd), buf, n);
  Exit;
{$endif}
  PyPalGetdents := -1;
  if NR_GETDENTS64 < 0 then Exit;
  PyPalGetdents := PyPalSys(NR_GETDENTS64, fd, Int64(buf), n, 0, 0, 0);
end;

function PyPalStatModeSize(path: Pointer; var mode: Int64; var size: Int64): Int64;
var buf: array[0..143] of Byte; r: Int64;
{$ifdef PXX_ESP_IDF}
    p: AnsiString;
{$endif}
begin
  mode := 0;
  size := 0;
  FillChar(buf[0], SizeOf(buf), 0);
{$ifdef PXX_ESP_IDF}
  p := EspPath(path);
  if p = ESP_FS_PREFIX + #0 then
  begin
    { FAT's VFS cannot stat its own mount point; the root is a directory }
    if EspOpendir(@p[1]) = nil then begin PyPalStatModeSize := EspFail; Exit; end;
    mode := $4000 or $1FF;
    PyPalStatModeSize := 0;
    Exit;
  end;
  r := EspStat(@p[1], @buf[0]);
  if r < 0 then begin PyPalStatModeSize := EspFail; Exit; end;
  mode := PLongWord(@buf[4])^;
  size := PLongWord(@buf[16])^;
  PyPalStatModeSize := 0;
{$else}
{$ifdef CPUX86_64}
  r := PyPalStat(path, @buf[0]);
  if r < 0 then begin PyPalStatModeSize := r; Exit; end;
  mode := PInt64(@buf[24])^ and $FFFFFFFF;   { u32 st_mode (uid sits above) }
  size := PInt64(@buf[48])^;
  PyPalStatModeSize := 0;
{$else}
  PyPalStatModeSize := -38;   { ENOSYS: no stat layout known for this target }
{$endif}
{$endif}
end;

function PyPalHasGetdents: Boolean;
begin
{$ifdef PXX_ESP_IDF}
  PyPalHasGetdents := True;
  Exit;
{$endif}
  PyPalHasGetdents := NR_GETDENTS64 >= 0;
end;

end.
