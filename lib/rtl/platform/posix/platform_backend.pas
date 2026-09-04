{ SPDX-License-Identifier: Zlib }
unit platform_backend;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ POSIX PAL backend selected by -Fulib/rtl/platform/posix. }

interface

uses platform_types;

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;

{ Dynamic loader primitives. Real only with -dPXX_DYNLIB_LIBC (dlopen/dlsym/
  dlclose via libc.so.6 — the binary then links libc, which the syscall-only
  core avoids, so it stays opt-in). Without the define these are honest nil/0
  stubs and PalBackendHasDynlib reports False. }
function PalBackendDlOpen(name: PChar): Pointer;
function PalBackendDlSym(handle: Pointer; sym: PChar): Pointer;
function PalBackendDlClose(handle: Pointer): Integer;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
function PalBackendFlush(handle: Integer): Integer;
function PalBackendClose(handle: Integer): Integer;
function PalBackendDelete(path: PChar): Integer;
function PalBackendRename(oldPath, newPath: PChar): Integer;
function PalBackendMkdir(path: PChar; mode: Integer): Integer;
function PalBackendRmdir(path: PChar): Integer;
function PalBackendChdir(path: PChar): Integer;
function PalBackendSymlink(target, linkpath: PChar): Integer;
function PalBackendLink(oldPath, newPath: PChar): Integer;
function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
function PalBackendSync: Integer;
function PalBackendSetsid: Integer;
function PalBackendGetGroups(count: Integer; list: Pointer): Integer;
function PalBackendGetPriority(which, who: Integer): Integer;
function PalBackendSetPriority(which, who, prio: Integer): Integer;
function PalBackendGetSid(pid: Integer): Integer;
function PalBackendRawSyscall(num, a1, a2, a3, a4, a5, a6: NativeInt): NativeInt;
function PalBackendSetPgid(pid, pgid: Integer): Integer;
function PalBackendGetPgid(pid: Integer): Integer;
function PalBackendAlarm(seconds: LongWord): Integer;
function PalBackendSetHostname(name: PChar; len: Integer): Integer;
function PalBackendSetGroups(count: Integer; list: Pointer): Integer;
function PalBackendSigTimedWait(setPtr: Pointer; setSize, sec, nsec: Integer): Integer;
function PalBackendSigProcMask(how: Integer; setPtr, oldSetPtr: Pointer; setSize: Integer): Integer;
function PalBackendClockSetTime(clockId: Integer; sec, nsec: Int64): Integer;
function PalBackendClockGetTime(clockId: Integer; var sec, nsec: Int64): Integer;
function PalBackendExit(code: Integer): Integer;
function PalBackendRandomBytes(buf: Pointer; n: Integer): Integer;
function PalBackendFsync(handle: Integer): Integer;
function PalBackendFdatasync(handle: Integer): Integer;
function PalBackendFchmod(handle, mode: Integer): Integer;
function PalBackendChmod(path: PChar; mode: Integer): Integer;
function PalBackendChown(path: PChar; owner, group: Integer): Integer;
function PalBackendLchown(path: PChar; owner, group: Integer): Integer;
function PalBackendPrlimit(resource: Integer; newLim, oldLim: Pointer): Integer;
function PalBackendUname(buf: Pointer): Integer;
function PalBackendTimes(buf: Pointer): Int64;
function PalBackendTruncate(path: PChar; length: Int64): Integer;
function PalBackendMknod(path: PChar; mode: Integer; dev: Int64): Integer;
function PalBackendUmask(mask: Integer): Integer;
function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
function PalBackendAccess(path: PChar; mode: Integer): Integer;
function PalBackendFchown(handle, owner, group: Integer): Integer;
function PalBackendGeteuid: Integer;
function PalBackendGetuid: Integer;
function PalBackendGetgid: Integer;
function PalBackendGetegid: Integer;
function PalBackendGetppid: Integer;
function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
function PalBackendGetpid: Integer;
function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
function PalBackendNanosleep(sec, nsec: Int64): Integer;
function PalBackendRealtime(var sec, nsec: Int64): Integer;
function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
function PalBackendUtimensat(dirFd: Integer; path: PChar;
                            aSec, aNsec, mSec, mNsec: Int64;
                            flags: Integer): Integer;
function PalBackendMmapAnon(len: Int64): Pointer;
function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
function PalBackendMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
function PalBackendIgnoreSignal(sig: Integer): Integer;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr;
                            port, scopeId: Integer): Integer;
function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr;
                               port, scopeId: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;
function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer;
                              const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer;
                                var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
function PalBackendGetSockError(handle: Integer): Integer;
function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr;
                              var outPort, outScopeId: Integer): Integer;

function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;

function PalBackendFork: Integer;
function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalBackendDup2(oldFd, newFd: Integer): Integer;
function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalBackendKill(pid, sig: Integer): Integer;
function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

{$ifdef CPU_AARCH64}{$define PAL_GENERIC_SYSCALLS}{$endif}
{$ifdef CPU_RISCV32}{$define PAL_GENERIC_SYSCALLS}{$endif}
{ xtensa fits the generic CALLING SHAPE — no fork, no vfork, no socketcall; it
  has clone(116), dup3(310) and the direct socket syscalls — but NOT the generic
  NUMBERING. That distinction is why SYS_exit exists below. }
{$ifdef CPU_XTENSA}{$define PAL_GENERIC_SYSCALLS}{$endif}

const
  PAL_PLATFORM_POSIX = 1;
  { A send to a peer that has closed must return EPIPE, not kill the process
    with SIGPIPE. Same value on every Linux arch. }
  MSG_NOSIGNAL = $4000;

{$ifdef CPUX86_64}
  SYS_read = 0; SYS_write = 1; SYS_close = 3; SYS_lseek = 8;
  SYS_sync = 162;      { /usr/include/.../asm/unistd_64.h __NR_sync }
  SYS_setsid = 112; SYS_getgroups = 115;   { asm/unistd_64.h }
  SYS_getpriority = 140; SYS_setpriority = 141; SYS_getsid = 124;   { asm/unistd_64.h }
  SYS_setpgid = 109; SYS_getpgid = 121;    { asm/unistd_64.h }
  SYS_setitimer = 38; SYS_sethostname = 170; SYS_setgroups = 116; SYS_rt_sigtimedwait = 128;  { asm/unistd_64.h }
  SYS_rt_sigprocmask = 14;                 { asm/unistd_64.h }
  SYS_clock_settime = 227;                 { asm/unistd_64.h }
  SYS_fsync = 74; SYS_fdatasync = 75; SYS_openat = 257; SYS_mkdirat = 258; SYS_getdents64 = 217; SYS_statx = 332;
  SYS_chdir = 80; SYS_linkat = 265; SYS_symlinkat = 266;
  SYS_unlinkat = 263; SYS_renameat = 264;
  SYS_socket=41; SYS_connect=42; SYS_accept4=288; SYS_bind=49; SYS_listen=50;
  SYS_setsockopt=54; SYS_shutdown=48; SYS_fcntl=72;
  SYS_getsockopt=55; SYS_getsockname=51; SYS_getpeername=52; SYS_ioctl=16;
  SYS_sendto=44; SYS_recvfrom=45; SYS_ppoll=271;
  SYS_vfork = 58; SYS_fork = 57; SYS_execve = 59; SYS_pipe2 = 293; SYS_dup2 = 33; SYS_wait4 = 61; SYS_kill = 62;
  SYS_clock_gettime = 228;
  SYS_mmap = 9; SYS_munmap = 11; SYS_mprotect = 10; SYS_fchmod = 91; SYS_getpid = 39; SYS_nanosleep = 35; SYS_utimensat = 280;
  SYS_fchmodat = 268; SYS_fchownat = 260; SYS_umask = 95;
  SYS_getcwd = 79; SYS_rt_sigaction = 13;
  SYS_truncate = 76; SYS_mknodat = 259; SYS_times = 100; SYS_uname = 63; SYS_prlimit64 = 302;
  SYS_ftruncate = 77; SYS_faccessat = 269; SYS_geteuid = 107; SYS_fchown = 93; SYS_readlinkat = 267;
  SYS_getuid = 102; SYS_getgid = 104; SYS_getegid = 108; SYS_getppid = 110;
  SYS_exit = 60;
  SYS_exit_group = 231;
  SYS_getrandom = 318;
{$endif}
{$ifdef CPU_I386}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_lseek = 19;
  SYS_sync = 36;       { asm/unistd_32.h __NR_sync }
  SYS_setsid = 66; SYS_getgroups = 205;    { asm/unistd_32.h: getgroups32, NOT the 16-bit-gid getgroups(80) -- the same *32 choice this file already makes for getuid }
  SYS_getpriority = 96; SYS_setpriority = 97; SYS_getsid = 147;      { asm/unistd_32.h }
  SYS_setpgid = 57; SYS_getpgid = 132;     { asm/unistd_32.h }
  SYS_setitimer = 104; SYS_sethostname = 74; SYS_setgroups = 206; SYS_rt_sigtimedwait = 177;  { asm/unistd_32.h -- setgroups32(206), the same *32 choice this file makes for getgroups }
  SYS_rt_sigprocmask = 175;                { asm/unistd_32.h }
  SYS_clock_settime = 264;                 { asm/unistd_32.h, one below clock_gettime(265) }
  SYS_fsync = 118; SYS_fdatasync = 148; SYS_openat = 295; SYS_mkdirat = 296; SYS_getdents64 = 220; SYS_statx = 383;
  SYS_chdir = 12; SYS_linkat = 303; SYS_symlinkat = 304;
  SYS_unlinkat = 301; SYS_renameat = 302;
  SYS_socketcall=102; SYS_fcntl=55;
  SC_SOCKET=1; SC_BIND=2; SC_CONNECT=3; SC_LISTEN=4; SC_ACCEPT4=18;
  SC_SETSOCKOPT=14; SC_SHUTDOWN=13; SC_SENDTO=11; SC_RECVFROM=12;
  SC_GETSOCKNAME=6; SC_GETSOCKOPT=15; SC_GETPEERNAME=7;
  SYS_ioctl=54;
  SYS_ppoll=309;
  SYS_vfork = 190; SYS_fork = 2; SYS_execve = 11; SYS_pipe2 = 331; SYS_dup2 = 63; SYS_wait4 = 114; SYS_kill = 37;
  SYS_clock_gettime = 265;
  SYS_mmap = 192; SYS_munmap = 91; SYS_mprotect = 125; SYS_fchmod = 94; SYS_getpid = 20; SYS_nanosleep = 162; SYS_utimensat = 320;
  SYS_fchmodat = 306; SYS_fchownat = 298; SYS_umask = 60;
  SYS_getcwd = 183; SYS_rt_sigaction = 174;
  SYS_truncate = 92; SYS_mknodat = 297; SYS_times = 43; SYS_uname = 122; SYS_prlimit64 = 340;
  SYS_ftruncate = 93; SYS_faccessat = 307; SYS_geteuid = 201; SYS_fchown = 207; SYS_readlinkat = 305;
  SYS_getuid = 199; SYS_getgid = 200; SYS_getegid = 202; SYS_getppid = 64;
  SYS_exit = 1;
  SYS_exit_group = 252;
  SYS_getrandom = 355;
{$endif}
{$ifdef CPU_AARCH64}
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_lseek = 62;
  SYS_sync = 81;       { asm-generic: sync(81) sits directly below fsync(82) }
  SYS_setsid = 157; SYS_getgroups = 158;   { asm-generic/unistd.h }
  SYS_getpriority = 141; SYS_setpriority = 140; SYS_getsid = 156;    { asm-generic/unistd.h -- note get/set are SWAPPED relative to the x86 tables }
  SYS_setpgid = 154; SYS_getpgid = 155;    { asm-generic/unistd.h }
  SYS_setitimer = 103; SYS_sethostname = 161; SYS_setgroups = 159; SYS_rt_sigtimedwait = 137;  { asm-generic/unistd.h }
  SYS_rt_sigprocmask = 135;                { asm-generic/unistd.h }
  SYS_clock_settime = 112;                 { asm-generic, one below clock_gettime(113) }
  SYS_fsync = 82; SYS_fdatasync = 83; SYS_openat = 56; SYS_mkdirat = 34; SYS_getdents64 = 61; SYS_statx = 291;
  SYS_chdir = 49; SYS_linkat = 37; SYS_symlinkat = 36;
  SYS_unlinkat = 35; SYS_renameat = 38;
  SYS_socket=198; SYS_connect=203; SYS_accept4=242; SYS_bind=200; SYS_listen=201;
  SYS_setsockopt=208; SYS_shutdown=210; SYS_fcntl=25;
  SYS_getsockopt=209; SYS_getsockname=204; SYS_getpeername=205; SYS_ioctl=29;
  SYS_sendto=206; SYS_recvfrom=207; SYS_ppoll=73;
  SYS_clone = 220; SYS_execve = 221; SYS_pipe2 = 59; SYS_dup3 = 24; SYS_wait4 = 260; SYS_kill = 129;
  SYS_clock_gettime = 113;
  SYS_mmap = 222; SYS_munmap = 215; SYS_mprotect = 226; SYS_fchmod = 52; SYS_getpid = 172; SYS_nanosleep = 101; SYS_utimensat = 88;
  SYS_fchmodat = 53; SYS_fchownat = 54; SYS_umask = 166;
  SYS_getcwd = 17; SYS_rt_sigaction = 134;
  SYS_truncate = 45; SYS_mknodat = 33; SYS_times = 153; SYS_uname = 160; SYS_prlimit64 = 261;
  SYS_ftruncate = 46; SYS_faccessat = 48; SYS_geteuid = 175; SYS_fchown = 55; SYS_readlinkat = 78;
  SYS_getuid = 174; SYS_getgid = 176; SYS_getegid = 177; SYS_getppid = 173;
  SYS_exit = 93;
  SYS_exit_group = 94;
  SYS_getrandom = 278;
{$endif}
{$ifdef CPU_ARM32}
  SYS_read = 3; SYS_write = 4; SYS_close = 6; SYS_lseek = 19;
  SYS_sync = 36;       { arm EABI keeps the legacy low numbers, as i386 does }
  SYS_setsid = 66; SYS_getgroups = 205;    { arm EABI, getgroups32 as on i386 }
  SYS_getpriority = 96; SYS_setpriority = 97; SYS_getsid = 147;      { arm EABI, the legacy numbers as on i386 }
  SYS_setpgid = 57; SYS_getpgid = 132;     { arm EABI, the legacy numbers as on i386 }
  SYS_setitimer = 104; SYS_sethostname = 74; SYS_setgroups = 206; SYS_rt_sigtimedwait = 177;  { arm EABI, the legacy numbers as on i386 }
  SYS_rt_sigprocmask = 175;                { arm EABI, as i386 }
  SYS_clock_settime = 262;                 { arm EABI, one below this table's own clock_gettime(263) -- the same -1 relation i386 and asm-generic show, read off this file rather than recalled }
  SYS_fsync = 118; SYS_fdatasync = 148; SYS_openat = 322; SYS_mkdirat = 323; SYS_getdents64 = 217; SYS_statx = 397;
  SYS_chdir = 12; SYS_linkat = 330; SYS_symlinkat = 331;
  SYS_unlinkat = 328; SYS_renameat = 329;
  SYS_socket=281; SYS_connect=283; SYS_accept4=366; SYS_bind=282; SYS_listen=284;
  SYS_setsockopt=294; SYS_shutdown=293; SYS_fcntl=55;
  SYS_getsockopt=295; SYS_getsockname=286; SYS_getpeername=287; SYS_ioctl=54;
  SYS_sendto=290; SYS_recvfrom=292; SYS_ppoll=336;
  SYS_vfork = 190; SYS_fork = 2; SYS_execve = 11; SYS_pipe2 = 359; SYS_dup2 = 63; SYS_wait4 = 114; SYS_kill = 37;
  SYS_clock_gettime = 263;
  SYS_mmap = 192; SYS_munmap = 91; SYS_mprotect = 125; SYS_fchmod = 94; SYS_getpid = 20; SYS_nanosleep = 162; SYS_utimensat = 348;
  SYS_fchmodat = 333; SYS_fchownat = 325; SYS_umask = 60;
  SYS_getcwd = 183; SYS_rt_sigaction = 174;
  SYS_truncate = 92; SYS_mknodat = 324; SYS_times = 43; SYS_uname = 122; SYS_prlimit64 = 369;
  SYS_ftruncate = 93; SYS_faccessat = 334; SYS_geteuid = 201; SYS_fchown = 207; SYS_readlinkat = 332;
  SYS_getuid = 199; SYS_getgid = 200; SYS_getegid = 202; SYS_getppid = 64;
  SYS_exit = 1;
  SYS_exit_group = 248;
  SYS_getrandom = 384;
{$endif}
{$ifdef CPU_RISCV32}
  { rv32 linux = asm-generic table (same slots as aarch64). 32-bit quirks:
    62 is _llseek(fd, off_hi, off_lo, loff_t *result, whence), NOT plain lseek —
    rv32 has no plain lseek at all. A 3-arg call leaves the result pointer NULL,
    the kernel returns EINVAL, and the -1 flows onward as a size. So a caller
    must split the 64-bit offset and pass the address of a local to receive the
    new position: see PalBackendSeek below, and the identical arm in PXXSysLseek
    (compiler/builtin/builtinheap.pas) — the two must not drift.

    This sentence previously said qemu-user tolerated the plain form for small
    offsets. It does not, and the correction is a measurement rather than a
    reading — qemu-riscv32 -strace, 2026-08-30:

      openat(AT_FDCWD,"test/hello.pas",O_RDONLY) = 3
      llseek(3,0,2,NULL,UNKNOWN)                 = -1 errno=22 (Invalid argument)
      read(3,0x2b2ad050,-22)                     = -1 errno=14 (Bad address)

    The stale claim cost a debugging cycle: a new caller was written to it and
    produced a LoadFile returning an empty string with no error anywhere.

    The time-related calls keep the legacy generic numbers qemu implements. }
  SYS_read = 63; SYS_write = 64; SYS_close = 57; SYS_lseek = 62;
  SYS_sync = 81;       { asm-generic, the same table aarch64 uses }
  SYS_setsid = 157; SYS_getgroups = 158;   { asm-generic, the same table aarch64 uses }
  SYS_getpriority = 141; SYS_setpriority = 140; SYS_getsid = 156;    { asm-generic, the same table aarch64 uses }
  SYS_setpgid = 154; SYS_getpgid = 155;    { asm-generic, the same table aarch64 uses }
  SYS_setitimer = 103; SYS_sethostname = 161; SYS_setgroups = 159; SYS_rt_sigtimedwait = 137;  { asm-generic, the same table aarch64 uses }
  SYS_rt_sigprocmask = 135;                { asm-generic, the same table aarch64 uses }
  SYS_clock_settime = 112;                 { asm-generic; rv32's time calls keep the legacy generic numbers qemu implements, as the note above says of clock_gettime }
  SYS_fsync = 82; SYS_fdatasync = 83; SYS_openat = 56; SYS_mkdirat = 34; SYS_getdents64 = 61; SYS_statx = 291;
  SYS_chdir = 49; SYS_linkat = 37; SYS_symlinkat = 36;
  SYS_unlinkat = 35; SYS_renameat = 38;
  SYS_socket=198; SYS_connect=203; SYS_accept4=242; SYS_bind=200; SYS_listen=201;
  SYS_setsockopt=208; SYS_shutdown=210; SYS_fcntl=25;
  SYS_getsockopt=209; SYS_getsockname=204; SYS_getpeername=205; SYS_ioctl=29;
  SYS_sendto=206; SYS_recvfrom=207; SYS_ppoll=73;
  SYS_clone = 220; SYS_execve = 221; SYS_pipe2 = 59; SYS_dup3 = 24; SYS_wait4 = 260; SYS_kill = 129;
  SYS_clock_gettime = 113;
  SYS_mmap = 222; SYS_munmap = 215; SYS_mprotect = 226; SYS_fchmod = 52; SYS_getpid = 172; SYS_nanosleep = 101; SYS_utimensat = 88;
  SYS_fchmodat = 53; SYS_fchownat = 54; SYS_umask = 166;
  SYS_getcwd = 17; SYS_rt_sigaction = 134;
  SYS_truncate = 45; SYS_mknodat = 33; SYS_times = 153; SYS_uname = 160; SYS_prlimit64 = 261;
  SYS_ftruncate = 46; SYS_faccessat = 48; SYS_geteuid = 175; SYS_fchown = 55; SYS_readlinkat = 78;
  SYS_getuid = 174; SYS_getgid = 176; SYS_getegid = 177; SYS_getppid = 173;
  SYS_exit = 93;
  SYS_exit_group = 94;
  SYS_getrandom = 278;
{$endif}
{$ifdef CPU_XTENSA}
  { xtensa linux has its OWN numbering — neither asm-generic nor i386's. These
    were MEASURED, not recalled: one syscall per process under `qemu-xtensa
    -strace`, every argument 2147483647 so the call is inert whatever it turns
    out to be (unmapped as a pointer, out of range as an fd, nonexistent AND
    positive as a pid so it can never mean a process group). All five values
    this repo had already established independently come back exactly:
    read=12, write=13, mmap2=80, exit=118, exit_group=119.
      A many-syscalls-per-process scan gave mmap2=79 — qemu kills the process on
    a bogus bind, the restart loses a number, and every row after it is off by
    one. Plausible and wrong is this repo's expensive shape; one per process is
    what makes the table trustworthy.
      lseek: xtensa has BOTH plain lseek(15) and _llseek(17), so unlike rv32
    (whose 62 IS _llseek) the ordinary 3-arg PalBackendSeek path is correct and
    no arm is added there. 32-bit off_t, same small-offset bound rv32 records.
      mmap: 80 is mmap2, matching i386's 192 and arm32's 192 — the call sites
    already pass a page offset of 0. }
  SYS_read = 12; SYS_write = 13; SYS_close = 9; SYS_lseek = 15;
  SYS_fsync = 26; SYS_openat = 288; SYS_mkdirat = 289; SYS_getdents64 = 60; SYS_statx = 351;
  SYS_chdir = 41; SYS_linkat = 293; SYS_symlinkat = 294;
  SYS_unlinkat = 291; SYS_renameat = 292;
  SYS_socket=96; SYS_connect=101; SYS_accept4=333; SYS_bind=100; SYS_listen=102;
  SYS_setsockopt=97; SYS_shutdown=99; SYS_fcntl=67;
  SYS_getsockopt=98; SYS_getsockname=104; SYS_getpeername=105; SYS_ioctl=66;
  SYS_sendto=110; SYS_recvfrom=111; SYS_ppoll=273;
  SYS_clone = 116; SYS_execve = 117; SYS_pipe2 = 311; SYS_dup3 = 310; SYS_wait4 = 121; SYS_kill = 123;
  SYS_clock_gettime = 245;
  SYS_mmap = 80; SYS_munmap = 81; SYS_mprotect = 82; SYS_fchmod = 52; SYS_getpid = 120; SYS_nanosleep = 195; SYS_utimensat = 296;
  SYS_fchmodat = 300; SYS_fchownat = 297; SYS_umask = 58;
  SYS_getcwd = 43; SYS_rt_sigaction = 226;
  SYS_truncate = 22; SYS_mknodat = 290;
  SYS_ftruncate = 23; SYS_faccessat = 301; SYS_geteuid = 140; SYS_fchown = 53; SYS_readlinkat = 295;
  SYS_getuid = 137; SYS_getgid = 139; SYS_getegid = 141; SYS_getppid = 150;
  SYS_exit = 118;
  SYS_exit_group = 119;
  SYS_getrandom = 338;
{$endif}
  PAL_AT_FDCWD = -100;
  PAL_AT_EMPTY_PATH = $1000;
  PAL_AT_SYMLINK_NOFOLLOW = $100;
  PAL_AT_REMOVEDIR = $200;
  PAL_STATX_BASIC_STATS = $000007FF;
  PAL_S_IFMT = $F000;
  PAL_S_IFDIR = $4000;
  PAL_S_IFREG = $8000;
  PAL_NET_AF_UNIX = 1;
  PAL_NET_AF_INET = 2;
  PAL_NET_AF_INET6 = 10;
  PAL_NET_ENAMETOOLONG = -36;   { a socket path too long for sun_path }
  { Linux ENOSYS, the portable "not here". Declared per backend rather than
    shared: platform_types carries types only, and the esp and wasi backends
    each already spell it out. posix needed it the moment the xtensa arms
    below started REFUSING a syscall instead of guessing its number. }
  PAL_ERR_UNSUPPORTED = -38;
  SOL_SOCKET = 1;
  SO_REUSEADDR = 2;
  SO_ERROR = 4;
  F_SETFL = 4;
  O_NONBLOCK = $800;

type
  PB = ^Byte;

{$ifdef CPU_I386}
function SockCall(callnr: Integer; a0, a1, a2, a3, a4: Int64): Int64;
var a: array[0..4] of NativeInt;
begin
  a[0] := a0; a[1] := a1; a[2] := a2; a[3] := a3; a[4] := a4;
  Result := __pxxrawsyscall(SYS_socketcall, callnr, Int64(@a[0]), 0, 0, 0, 0);
end;

function SockCall6(callnr: Integer; a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..5] of NativeInt;
begin
  a[0] := a0; a[1] := a1; a[2] := a2; a[3] := a3; a[4] := a4; a[5] := a5;
  Result := __pxxrawsyscall(SYS_socketcall, callnr, Int64(@a[0]), 0, 0, 0, 0);
end;
{$endif}

procedure FillSockAddrIpv4(sa: Pointer; hostAddr: LongWord; port: Integer);
var i: Integer;
begin
  for i := 0 to 15 do PB(Pointer(Int64(sa) + i))^ := 0;
  PB(Pointer(Int64(sa) + 0))^ := PAL_NET_AF_INET;
  PB(Pointer(Int64(sa) + 2))^ := (port shr 8) and $FF;
  PB(Pointer(Int64(sa) + 3))^ := port and $FF;
  PB(Pointer(Int64(sa) + 4))^ := (hostAddr shr 24) and $FF;
  PB(Pointer(Int64(sa) + 5))^ := (hostAddr shr 16) and $FF;
  PB(Pointer(Int64(sa) + 6))^ := (hostAddr shr 8) and $FF;
  PB(Pointer(Int64(sa) + 7))^ := hostAddr and $FF;
end;

procedure ParseSockAddrIpv4(sa: Pointer; var hostAddr: LongWord; var port: Integer);
begin
  port := (Integer(PB(Pointer(Int64(sa) + 2))^) shl 8) or Integer(PB(Pointer(Int64(sa) + 3))^);
  hostAddr := (LongWord(PB(Pointer(Int64(sa) + 4))^) shl 24)
           or (LongWord(PB(Pointer(Int64(sa) + 5))^) shl 16)
           or (LongWord(PB(Pointer(Int64(sa) + 6))^) shl 8)
           or  LongWord(PB(Pointer(Int64(sa) + 7))^);
end;

function PalBackendPlatform: Integer;
begin
  Result := PAL_PLATFORM_POSIX;
end;

function PalBackendHasFiles: Boolean;
begin
  Result := True;
end;

function PalBackendHasSockets: Boolean;
begin
  Result := True;
end;

function PalBackendHasThreads: Boolean;
begin
  Result := True;
end;

{$ifdef PXX_DYNLIB_LIBC}

const
  PAL_RTLD_NOW = 2;   { resolve all symbols at load time (Linux/glibc) }

{ dlopen/dlsym/dlclose live in libc.so.6 on modern glibc (>= 2.34; the old
  separate libdl is now an empty stub). The compiler emits the dynamic-link
  machinery (PT_INTERP, dynsym, GOT) for any `external '<soname>'` routine —
  which is exactly why these declarations sit behind the define. }
function c_dlopen(name: PChar; flag: Integer): Pointer; cdecl; external 'libc.so.6' name 'dlopen';
function c_dlsym(handle: Pointer; symbol: PChar): Pointer; cdecl; external 'libc.so.6' name 'dlsym';
function c_dlclose(handle: Pointer): Integer; cdecl; external 'libc.so.6' name 'dlclose';

function PalBackendHasDynlib: Boolean;
begin
  Result := True;
end;

function PalBackendDlOpen(name: PChar): Pointer;
begin
  Result := c_dlopen(name, PAL_RTLD_NOW);
end;

function PalBackendDlSym(handle: Pointer; sym: PChar): Pointer;
begin
  Result := c_dlsym(handle, sym);
end;

function PalBackendDlClose(handle: Pointer): Integer;
begin
  Result := c_dlclose(handle);
end;

{$else}

function PalBackendHasDynlib: Boolean;
begin
  { No loader in the libc-free build; opt in with -dPXX_DYNLIB_LIBC. }
  Result := False;
end;

function PalBackendDlOpen(name: PChar): Pointer;
begin
  Result := nil;
end;

function PalBackendDlSym(handle: Pointer; sym: PChar): Pointer;
begin
  Result := nil;
end;

function PalBackendDlClose(handle: Pointer): Integer;
begin
  Result := 0;
end;

{$endif}

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_openat, PAL_AT_FDCWD, Int64(path), flags, mode, 0, 0));
end;

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_read, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_write, handle, Int64(buf), len, 0, 0, 0);
end;

function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
{$ifdef CPU_RISCV32}
var res: Int64; r: Int64;
{$endif}
begin
{$ifdef CPU_RISCV32}
  { rv32 syscall 62 is _llseek(fd, off_hi, off_lo, loff_t *result, whence), NOT
    plain lseek — the 3-arg form left the result pointer NULL and the kernel
    faulted (EFAULT). Split the 64-bit offset and pass the address of a local to
    receive the new position. }
  res := 0;
  r := __pxxrawsyscall(SYS_lseek, handle, (offset shr 32) and $FFFFFFFF,
                       offset and $FFFFFFFF, Int64(@res), whence);
  if r < 0 then Result := r else Result := res;
{$else}
  Result := __pxxrawsyscall(SYS_lseek, handle, offset, whence, 0, 0, 0);
{$endif}
end;

function PalBackendFlush(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fsync, handle, 0, 0, 0, 0, 0));
end;

function PalBackendClose(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_close, handle, 0, 0, 0, 0, 0));
end;

function PalBackendIgnoreSignal(sig: Integer): Integer;
var act: array[0..3] of Int64;   { {sa_handler=SIG_IGN, flags, restorer, mask} }
begin
  { SIG_IGN (=1) is never invoked, so no SA_RESTORER/trampoline is needed. The
    4-Int64 layout gives handler=1, flags=0, restorer=0, mask=0 on both 32- and
    64-bit. sigsetsize = 8 (kernel 64-bit sigset). }
  act[0] := 1; act[1] := 0; act[2] := 0; act[3] := 0;
  Result := Integer(__pxxrawsyscall(SYS_rt_sigaction, sig, Int64(@act[0]), 0, 8, 0, 0));
end;

function PalBackendDelete(path: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_unlinkat, PAL_AT_FDCWD, Int64(path), 0, 0, 0, 0));
end;

function PalBackendRename(oldPath, newPath: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_renameat, PAL_AT_FDCWD, Int64(oldPath),
    PAL_AT_FDCWD, Int64(newPath), 0));
end;

function PalBackendMkdir(path: PChar; mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_mkdirat, PAL_AT_FDCWD, Int64(path), mode, 0, 0, 0));
end;

function PalBackendRmdir(path: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_unlinkat, PAL_AT_FDCWD, Int64(path),
    PAL_AT_REMOVEDIR, 0, 0, 0));
end;

function PalBackendChdir(path: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_chdir, Int64(path), 0, 0, 0, 0, 0));
end;

{ symlink/link go through the *at forms with AT_FDCWD (-100): aarch64 and riscv
  have no legacy symlink/link syscalls at all, so the *at variant is the only
  spelling that exists on every target — the same reason openat/unlinkat/
  renameat are used above. Note symlinkat takes (target, dirfd, linkpath), with
  the dirfd in the MIDDLE, unlike linkat's (olddirfd, old, newdirfd, new, flags). }
function PalBackendSymlink(target, linkpath: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_symlinkat, Int64(target), -100,
                                    Int64(linkpath), 0, 0, 0));
end;

function PalBackendLink(oldPath, newPath: PChar): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_linkat, -100, Int64(oldPath), -100,
                                    Int64(newPath), 0, 0));
end;

function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_ftruncate, handle, length, 0, 0, 0, 0));
end;

function PalBackendAccess(path: PChar; mode: Integer): Integer;
begin
  { access(path,mode) = faccessat(AT_FDCWD, path, mode, 0) — the plain access
    syscall is absent on the asm-generic table (aarch64/rv32). }
  Result := Integer(__pxxrawsyscall(SYS_faccessat, PAL_AT_FDCWD, Int64(path), mode, 0, 0, 0));
end;

function PalBackendFchown(handle, owner, group: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchown, handle, owner, group, 0, 0, 0));
end;

function PalBackendGeteuid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_geteuid, 0, 0, 0, 0, 0, 0));
end;

{ The remaining id calls. 32-bit targets use the *32 variants, as geteuid above
  already does — the legacy 16-bit ones truncate a modern uid. }
function PalBackendGetuid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getuid, 0, 0, 0, 0, 0, 0));
end;

function PalBackendGetgid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getgid, 0, 0, 0, 0, 0, 0));
end;

function PalBackendGetegid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getegid, 0, 0, 0, 0, 0, 0));
end;

function PalBackendGetppid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getppid, 0, 0, 0, 0, 0, 0));
end;

function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  { readlink(path,buf,n) = readlinkat(AT_FDCWD, path, buf, n). }
  Result := Integer(__pxxrawsyscall(SYS_readlinkat, PAL_AT_FDCWD, Int64(path),
    Int64(buf), bufsz, 0, 0));
end;

function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_getdents64, handle, Int64(buf), len, 0, 0, 0);
end;

function StatxByte(buf: Pointer; off: Integer): Byte;
begin
  Result := PB(Pointer(Int64(buf) + off))^;
end;

function StatxWordLE(buf: Pointer; off: Integer): Integer;
begin
  Result := Integer(StatxByte(buf, off)) + Integer(StatxByte(buf, off + 1)) * 256;
end;

function StatxDwordLE(buf: Pointer; off: Integer): Int64;
begin
  Result := Int64(StatxByte(buf, off)) + Int64(StatxByte(buf, off + 1)) * 256 +
            Int64(StatxByte(buf, off + 2)) * 65536 + Int64(StatxByte(buf, off + 3)) * 16777216;
end;

function StatxInt64LE(buf: Pointer; off: Integer): Int64;
var
  i: Integer;
  mul: Int64;
begin
  Result := 0;
  mul := 1;
  for i := 0 to 7 do
  begin
    Result := Result + Int64(StatxByte(buf, off + i)) * mul;
    mul := mul * 256;
  end;
end;

procedure ClearPalFileStat(var info: TPalFileStat);
begin
  info.Size := -1;
  info.MTimeSec := 0;
  info.Mode := 0;
  info.IsDir := False;
  info.IsFile := False;
  info.Ino := 0;
  info.Dev := 0;
  info.Blocks := 0;
  info.BlkSize := 4096;
  info.Nlink := 1;      { a plain file has one link; overwritten by a real stat }
  info.Uid := 0;
  info.Gid := 0;
  info.Rdev := 0;
  info.ATimeSec := 0;
  info.CTimeSec := 0;
end;

{ Pack a (major, minor) pair the way USERSPACE spells a dev_t -- the encoding
  the kernel calls new_encode_dev and glibc's makedev/major/minor implement:

    bits  7..0   minor, low 8      bits 19..12  minor, high 24
    bits 19..8   major, low 12     bits 63..32  major, high 20

  IT IS NOT THE KERNEL-INTERNAL MKDEV, which is a plain `(major shl 20) or
  minor`, and the two look identical on the common case in the wrong direction:
  MKDEV(1,3) is 0x100003 and every field of it decodes as a NUMBER, so nothing
  errors -- crtl's major() returns 0 and minor() returns 259 for /dev/null.
  Measured against glibc on the same box, same file: glibc's st_rdev is 0x103.

  Which one belongs in a struct stat is not a matter of taste: crtl's
  <sys/sysmacros.h> is transcribed from glibc's, and mknod(2) takes the
  userspace encoding too (the kernel new_decode_dev's it), so the internal
  spelling was the one value in the chain nobody could decode. The old code
  encoded BOTH st_dev and st_rdev this way; sqlite never noticed because it
  keys file identity on (dev, ino) as an opaque pair and any bijection serves.
  bug-a-stat-returns-st-dev-and-st-rdev-in-the-kernel-internal-encoding }
function EncodeDevUser(major, minor: Int64): Int64;
begin
  Result := (minor and $FF)
         or ((major and $FFF) shl 8)
         or ((minor and $FFFFFF00) shl 12)
         or ((major and $FFFFF000) shl 32);
end;

{ statx(2) — arch-neutral stat with a uniform struct layout on every target, so
  one field-offset map works for x86-64/i386/aarch64/arm32/riscv32 alike. }
function DoStatx(dirHandle: Integer; path: PChar; flags: Integer; var info: TPalFileStat): Integer;
var
  sx: array[0..255] of Byte;
  mode: Integer;
begin
  ClearPalFileStat(info);
  Result := Integer(__pxxrawsyscall(SYS_statx, dirHandle, Int64(path), flags,
    PAL_STATX_BASIC_STATS, Int64(@sx[0]), 0));
  if Result < 0 then Exit;

  mode := StatxWordLE(@sx[0], $1C);
  info.Mode := mode;
  info.BlkSize := Integer(StatxDwordLE(@sx[0], $04));
  info.Ino := StatxInt64LE(@sx[0], $20);
  info.Size := StatxInt64LE(@sx[0], $28);
  info.Blocks := StatxInt64LE(@sx[0], $30);
  info.MTimeSec := StatxInt64LE(@sx[0], $70);
  { the fields crtl used to hardcode. Offsets are the statx(2) layout, which is
    identical on every target — the same reason the ones above work unchanged. }
  info.Nlink := Int64(StatxDwordLE(@sx[0], $10));
  info.Uid := Integer(StatxDwordLE(@sx[0], $14));
  info.Gid := Integer(StatxDwordLE(@sx[0], $18));
  info.ATimeSec := StatxInt64LE(@sx[0], $40);
  info.CTimeSec := StatxInt64LE(@sx[0], $60);
  info.Rdev := EncodeDevUser(StatxDwordLE(@sx[0], $80), StatxDwordLE(@sx[0], $84));
  { stable (dev,ino) key for sqlite locks, AND a value major()/minor() can read }
  info.Dev := EncodeDevUser(StatxDwordLE(@sx[0], $88), StatxDwordLE(@sx[0], $8C));
  info.IsDir := (mode and PAL_S_IFMT) = PAL_S_IFDIR;
  info.IsFile := (mode and PAL_S_IFMT) = PAL_S_IFREG;
end;

function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
begin
  Result := DoStatx(dirHandle, path, 0, info);
end;

function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := DoStatx(PAL_AT_FDCWD, path, 0, info);
end;

function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := DoStatx(PAL_AT_FDCWD, path, PAL_AT_SYMLINK_NOFOLLOW, info);
end;

function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
var empty: array[0..0] of Byte;
begin
  empty[0] := 0;   { statx(fd, "", AT_EMPTY_PATH) = fstat }
  Result := DoStatx(handle, PChar(@empty[0]), PAL_AT_EMPTY_PATH, info);
end;

function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fcntl, handle, cmd, arg, 0, 0, 0));
end;

function PalBackendFsync(handle: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fsync, handle, 0, 0, 0, 0, 0));
end;

function PalBackendFdatasync(handle: Integer): Integer;
{ fdatasync(2): flush the DATA, and only as much metadata as a later read needs
  to find it. Distinct from fsync because the difference is the whole point --
  a caller that wanted the timestamps flushed too would have called fsync, and
  aliasing this onto fsync makes it correct and slow rather than wrong, which
  is why the alias is tempting and still not what the name says.

  NO XTENSA NUMBER, deliberately. That table's own comment says its values were
  MEASURED under qemu-xtensa one syscall per process, and adding a recalled
  number to it would put a guess under someone else's provenance claim -- where
  the next reader would inherit the measurement's credibility for a value
  nobody checked. A refusal here is recoverable; a wrong syscall number on a
  file descriptor is not. Measure it and this arm goes away. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_fdatasync, handle, 0, 0, 0, 0, 0));
{$endif}
end;

{ sync(2) -- flush ALL filesystem buffers. busybox's `sync' applet is the
  caller that wanted it.

  XTENSA REFUSES RATHER THAN GUESSES, and that is the whole reason this has an
  ifdef when PalBackendFsync does not. Every other table here comes from a
  source: x86-64 and i386 are read off this box's asm/unistd_{64,32}.h, and
  aarch64/riscv32 are asm-generic where sync(81) sits directly below fsync(82).
  The xtensa numbers in this file were obtained EMPIRICALLY, one syscall per
  process (see the note above their table), and sync was never among them. A
  guessed number does not fail -- it issues a DIFFERENT syscall, which is this
  repo's expensive shape. Measure it and delete this arm. }
function PalBackendSync: Integer;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_sync, 0, 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendSetsid: Integer;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setsid, 0, 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendGetGroups(count: Integer; list: Pointer): Integer;
{ getgroups(2). count=0 asks for the COUNT and must not write through list --
  that is the call every caller makes first, so it is the one that matters. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_getgroups, PtrUInt(count), PtrUInt(list), 0, 0, 0, 0));
{$endif}
end;

function PalBackendGetPriority(which, who: Integer): Integer;
{ getpriority(2), and the RAW kernel encoding is deliberate. A nice value is
  -20..19, so a syscall returning it directly could not tell a nice of -1 from
  EPERM. The kernel therefore returns 20-nice (1..40) and every real libc
  converts on the way out; this returns the kernel's number unchanged so that
  a negative result still means -errno on this side of the PAL, and the
  conversion happens once, in the crtl wrapper that owns errno. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_getpriority, PtrUInt(which), PtrUInt(who), 0, 0, 0, 0));
{$endif}
end;

function PalBackendSetPriority(which, who, prio: Integer): Integer;
{ setpriority(2). Takes the nice value as-is -- only the GET direction is
  biased; the kernel clamps out-of-range values rather than refusing them. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setpriority, PtrUInt(which), PtrUInt(who), PtrUInt(prio), 0, 0, 0));
{$endif}
end;

function PalBackendGetSid(pid: Integer): Integer;
{ getsid(2). pid=0 asks about the caller. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_getsid, PtrUInt(pid), 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendSetPgid(pid, pgid: Integer): Integer;
{ setpgid(2). Both zeros mean "the caller, into its own new group" -- which is
  what the BSD setpgrp() spelling reduces to. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setpgid, PtrUInt(pid), PtrUInt(pgid), 0, 0, 0, 0));
{$endif}
end;

function PalBackendGetPgid(pid: Integer): Integer;
{ getpgid(2). pid=0 asks about the caller. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_getpgid, PtrUInt(pid), 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendAlarm(seconds: LongWord): Integer;
{ alarm(2), over SETITIMER rather than over the alarm syscall.

  THERE IS NO alarm SYSCALL ON EVERY TARGET. x86-64, i386 and arm32 have one;
  the asm-generic table aarch64 and riscv32 use dropped it, and glibc
  implements alarm over setitimer there. Using setitimer EVERYWHERE means one
  path instead of two, and the two would not have been equivalent: the
  remaining-seconds result has to be ROUNDED UP from the old timer's
  microseconds, and a second implementation is a second place to get that
  rounding wrong. alarm(2) says a fractional second left rounds up to 1, never
  down to 0 -- 0 means "no alarm was pending", which is a different answer.

  struct itimerval is FOUR native words (two timevals), not four Int64s: on a
  32-bit target the kernel's timeval is two 32-bit fields. }
var
  newv, oldv: array[0..3] of NativeInt;
  rc: Int64;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  newv[0] := 0; newv[1] := 0;                 { it_interval: one-shot }
  newv[2] := NativeInt(seconds); newv[3] := 0;{ it_value }
  oldv[0] := 0; oldv[1] := 0; oldv[2] := 0; oldv[3] := 0;
  rc := __pxxrawsyscall(SYS_setitimer, 0 { ITIMER_REAL }, PtrUInt(@newv[0]), PtrUInt(@oldv[0]), 0, 0, 0);
  if rc < 0 then
  begin
    Result := Integer(rc);
    Exit;
  end;
  Result := Integer(oldv[2]);
  if oldv[3] > 0 then Inc(Result);            { round a part-second UP, per alarm(2) }
{$endif}
end;

function PalBackendSetHostname(name: PChar; len: Integer): Integer;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_sethostname, PtrUInt(name), PtrUInt(len), 0, 0, 0, 0));
{$endif}
end;

function PalBackendSetGroups(count: Integer; list: Pointer): Integer;
{ setgroups(2). i386 and arm32 take setgroups32, NOT the 16-bit-gid
  setgroups(81) -- the same *32 choice this file already makes for getgroups
  and getuid. Passing 32-bit gids to the 16-bit call truncates every gid above
  65535 to a DIFFERENT existing group. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setgroups, PtrUInt(count), PtrUInt(list), 0, 0, 0, 0));
{$endif}
end;

function PalBackendSigTimedWait(setPtr: Pointer; setSize, sec, nsec: Integer): Integer;
{ sigtimedwait(2) with a NULL siginfo -- returns the signal number, or -EAGAIN
  on timeout.

  THE FOURTH ARGUMENT IS THE SIGSET SIZE IN BYTES and the kernel REJECTS a
  wrong one with EINVAL rather than reading what it was given, which is the one
  mercy in the rt_sig* family. It is the caller's sizeof(sigset_t), passed in
  rather than assumed here, because crtl's sigset_t and the kernel's need not
  agree in width and the caller is the one that knows.

  A negative `sec' means "no timeout": a NULL timespec pointer, which blocks. }
var
  ts: array[0..1] of NativeInt;
  tsp: PtrUInt;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  ts[0] := NativeInt(sec);
  ts[1] := NativeInt(nsec);
  if sec < 0 then tsp := 0 else tsp := PtrUInt(@ts[0]);
  Result := Integer(__pxxrawsyscall(SYS_rt_sigtimedwait, PtrUInt(setPtr), 0, tsp,
                                    PtrUInt(setSize), 0, 0));
{$endif}
end;

function PalBackendSigProcMask(how: Integer; setPtr, oldSetPtr: Pointer; setSize: Integer): Integer;
{ rt_sigprocmask(2). `setSize' is the KERNEL's sigset width in bytes -- 8 on
  every Linux architecture, because _NSIG is 64 -- and the kernel REJECTS any
  other value with EINVAL rather than reading what it was handed. The caller
  passes it because the caller's own sigset_t need not be that width, and it is
  the caller that knows which eight bytes to point at. }
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_rt_sigprocmask, PtrUInt(how), PtrUInt(setPtr),
                                    PtrUInt(oldSetPtr), PtrUInt(setSize), 0, 0));
{$endif}
end;

function PalBackendRawSyscall(num, a1, a2, a3, a4, a5, a6: NativeInt): NativeInt;
{ THE RAW SYSCALL BRIDGE, and it is deliberately the only place in this file
  that does not name what it is doing. Everything else here is a PAL entry with
  a contract the non-Linux backends can refuse in terms of; this one hands the
  caller the kernel interface directly, which is what a C program spelling
  syscall(2) is asking for -- busybox's ionice and modutils issue ioprio_get
  and finit_module that way, and the alternative is a bespoke PAL entry per
  exotic call, each one used once.

  It returns the kernel's answer UNTRANSLATED: negative is -errno, as for every
  other entry here, and the C wrapper converts. There is no argument checking
  and none is possible -- the number decides what the six words mean. }
begin
  Result := NativeInt(__pxxrawsyscall(PtrUInt(num), PtrUInt(a1), PtrUInt(a2),
                                      PtrUInt(a3), PtrUInt(a4), PtrUInt(a5), PtrUInt(a6)));
end;

function PalBackendClockSetTime(clockId: Integer; sec, nsec: Int64): Integer;
{ clock_settime(2). The kernel takes a `struct timespec', so the two halves are
  marshalled here rather than passed as registers -- and it is TWO NATIVE
  WORDS, not two Int64s: on a 32-bit target the kernel's timespec is 32-bit and
  handing it a 16-byte one writes past the struct it was given.

  Almost every call fails with EPERM, which is correct and is not a stub: only
  root may set the clock. A caller that cannot tell "refused" from "not
  implemented" is exactly what a stub would have produced. }
var ts: array[0..1] of NativeInt;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  ts[0] := NativeInt(sec);
  ts[1] := NativeInt(nsec);
  Result := Integer(__pxxrawsyscall(SYS_clock_settime, PtrUInt(clockId), PtrUInt(@ts[0]), 0, 0, 0, 0));
{$endif}
end;

function PalBackendFchmod(handle, mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchmod, handle, mode, 0, 0, 0, 0));
end;

{ chmod BY PATH goes through fchmodat(AT_FDCWD, path, mode, 0): aarch64 and
  riscv have no legacy chmod syscall at all, exactly like symlink/link above.
  AT_FDCWD = -100. }
function PalBackendChmod(path: PChar; mode: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchmodat, -100, Int64(path), mode, 0, 0, 0));
end;

{ chown / lchown, both through fchownat for the same reason chmod goes through
  fchmodat: aarch64 and riscv have no legacy chown syscall at all. AT_FDCWD =
  -100; AT_SYMLINK_NOFOLLOW = $100 is the ONLY difference between the two, and
  it is the whole difference -- lchown must change the SYMLINK, not what it
  points at, which is why busybox's libbb/copy_file.c calls it when preserving
  ownership of a copied tree. Getting that flag wrong silently chowns the
  wrong inode. }
function PalBackendChown(path: PChar; owner, group: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchownat, -100, Int64(path), owner, group, 0, 0));
end;

function PalBackendLchown(path: PChar; owner, group: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_fchownat, -100, Int64(path), owner, group, $100, 0));
end;

{ truncate by PATH. Unlike chown there IS a legacy syscall on every target
  here, including the asm-generic ones (45), so this does not go through an
  *at variant -- there is no truncateat. }
function PalBackendTruncate(path: PChar; length: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_truncate, Int64(path), length, 0, 0, 0, 0));
end;

{ mknod, through mknodat for the same reason chmod goes through fchmodat: the
  asm-generic targets have no legacy mknod. `dev` is only consulted for
  S_IFCHR/S_IFBLK; a FIFO or a regular file ignores it, which is the case real
  code (busybox's libbb/copy_file.c, recreating a device node while copying a
  tree) reaches most often. }
function PalBackendMknod(path: PChar; mode: Integer; dev: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_mknodat, -100, Int64(path), mode, dev, 0, 0));
end;

{ times(2): fills a `struct tms` -- FOUR kernel clock_t, which are target-word
  `long`, NOT long long -- and RETURNS ticks since an arbitrary point in the
  past rather than 0-on-success. So a caller cannot test this for `= 0`; the
  error case is the usual negative errno and every other value is data.

  The struct is shared with the kernel, so its member width is an ABI fact, not
  a choice. busybox's ash reads it as `*(clock_t *)((char *)&buf + offset)` --
  by BYTE OFFSET, cast through clock_t -- so a clock_t wider than the member
  silently reads two fields as one on any 32-bit target. crtl's clock_t is
  `long` for exactly this reason (lib/crtl/include/time.h).

  SYS_times numbers: x86-64 100 and i386 43 read off the host's
  asm/unistd_{64,32}.h; aarch64 and riscv32 both 153 from asm-generic/unistd.h,
  which the riscv32 block above already documents itself as following; arm32 43
  from the legacy table it shares with i386 -- consistent with every other
  legacy entry here (truncate 92, fchown 207, getuid 199, exit 1 all match).
  XTENSA REFUSES rather than guessing: its table is bespoke, and every xtensa
  number in this file was MEASURED under `qemu-xtensa -strace` one syscall per
  process, precisely because a plausible-looking wrong number is a syscall that
  quietly does something else. Measure it the same way before filling it in. }
function PalBackendTimes(buf: Pointer): Int64;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := __pxxrawsyscall(SYS_times, Int64(buf), 0, 0, 0, 0, 0);
{$endif}
end;

{ uname(2). Fills a `struct utsname`: SIX fixed 65-byte char arrays back to
  back, 390 bytes total, no padding -- measured against glibc (offsets
  0,65,130,195,260,325). That is the kernel's `new_utsname` and the layout is
  an ABI fact.

  Numbers: x86-64 63 and i386 122 read off the host's asm/unistd_{64,32}.h
  individually (a combined grep printed them in an order that did not match the
  file order, which is exactly the kind of thing worth re-reading rather than
  squinting at); aarch64 and riscv32 160 from asm-generic/unistd.h; arm32 122
  from the legacy table it shares with i386. XTENSA REFUSES -- same reason as
  PalBackendTimes above: its table is bespoke and measured, never inferred. }
function PalBackendUname(buf: Pointer): Integer;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_uname, Int64(buf), 0, 0, 0, 0, 0));
{$endif}
end;

{ prlimit64: the ONE syscall behind both getrlimit and setrlimit.
  prlimit64(pid, resource, newLimit, oldLimit) with pid 0 meaning "me". The
  legacy getrlimit/setrlimit/ugetrlimit calls use a 32-bit rlim_t on 32-bit
  targets and saturate at 4GB; prlimit64 is 64-bit everywhere and exists on
  every kernel pxx targets, so there is one code path instead of a per-word-size
  pair. Either pointer may be nil: nil newLimit is a pure query, nil oldLimit a
  pure set.

  Numbers: x86-64 302 and i386 340 from the host's asm/unistd_{64,32}.h;
  aarch64 and riscv32 261 from asm-generic. ARM32 369 is the legacy table's
  slot and is the one number here I could not read off a header on this box, so
  it is VERIFIED BY RUNNING rather than asserted -- test/crlimit.c is executed
  under qemu-arm by the arm32 row, and a wrong number would answer with an
  error or with garbage instead of the host's real RLIMIT_NOFILE.
  XTENSA REFUSES: bespoke table, and its numbers are measured under
  qemu-xtensa -strace, never inferred. }
function PalBackendPrlimit(resource: Integer; newLim, oldLim: Pointer): Integer;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  Result := Integer(__pxxrawsyscall(SYS_prlimit64, 0, resource,
                                    Int64(newLim), Int64(oldLim), 0, 0));
{$endif}
end;

{ umask always succeeds and returns the PREVIOUS mask — it has no error case,
  which is why it is the one syscall here with no negative-errno path. }
function PalBackendUmask(mask: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_umask, mask, 0, 0, 0, 0, 0));
end;

function PalBackendGetpid: Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getpid, 0, 0, 0, 0, 0, 0));
end;

{ Returns the path length INCLUDING the trailing NUL, or -errno. }
function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_getcwd, Int64(buf), size, 0, 0, 0, 0));
end;

function PalBackendNanosleep(sec, nsec: Int64): Integer;
var ts: array[0..1] of NativeInt;   { struct timespec (tv_sec; tv_nsec), native-word fields per arch }
begin
  ts[0] := NativeInt(sec); ts[1] := NativeInt(nsec);
  Result := Integer(__pxxrawsyscall(SYS_nanosleep, Int64(@ts[0]), 0, 0, 0, 0, 0));
end;

function PalBackendRealtime(var sec, nsec: Int64): Integer;
var ts: array[0..1] of NativeInt;
begin
  ts[0] := 0; ts[1] := 0;
  Result := Integer(__pxxrawsyscall(SYS_clock_gettime, 0, Int64(@ts[0]), 0, 0, 0, 0)); { 0 = CLOCK_REALTIME }
  sec := ts[0]; nsec := ts[1];
end;

function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
var ts: array[0..3] of NativeInt;  { struct timespec[2] (atime, mtime) }
begin
  ts[0] := NativeInt(atimeSec); ts[1] := 0;
  ts[2] := NativeInt(mtimeSec); ts[3] := 0;
  Result := Integer(__pxxrawsyscall(SYS_utimensat, PAL_AT_FDCWD, Int64(path), Int64(@ts[0]), 0, 0, 0));
end;

{ The general clock_gettime(2). PalBackendRealtime above is this with clockId 0,
  and stays a separate entry because it is the hot one and its callers have no
  clock to pass.

  TWO NATIVE WORDS, not two Int64s -- the same rule PalBackendClockSetTime states
  for the write direction, and for the same reason: on a 32-bit target the
  kernel's timespec is 32-bit. The widening into the Int64 outputs is IMPLICIT
  and must stay that way (bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit).

  Note for whoever fixes riscv32: 113 is the asm-generic clock_gettime and rv32
  does not have it -- measured -38 (-ENOSYS) here, same rv32 time64 story as
  nanosleep. See bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall,
  which covers the whole family rather than one entry. }
function PalBackendClockGetTime(clockId: Integer; var sec, nsec: Int64): Integer;
var ts: array[0..1] of NativeInt;
begin
  ts[0] := 0; ts[1] := 0;
  Result := Integer(__pxxrawsyscall(SYS_clock_gettime, clockId, Int64(@ts[0]), 0, 0, 0, 0));
  sec := ts[0]; nsec := ts[1];
end;

{ exit_group(code), with exit(code) behind it.

  BOTH, and in that order, because they answer different questions: exit_group
  ends every thread and exit ends only the calling one, so a single-threaded
  program is served by either and a threaded one is only served by the first.
  If exit_group somehow returns, falling through to exit is better than letting
  the caller run on with the process alive.

  THE NUMBER IS PER TARGET AND GETTING IT WRONG IS SILENT. This was hardcoded to
  231 in pxxcio.pas -- x86-64's number -- and on i386 231 is fgetxattr, so C's
  `exit(3)` quietly failed an xattr call, returned, and the process exited 0:
  every i386 program that reported failure through exit() reported SUCCESS.
  `return 3` from main was unaffected, which is why nothing caught it. It now
  lives here, once, beside the other numbers for the same target. }
function PalBackendExit(code: Integer): Integer;
var ignored: Int64;
begin
  ignored := __pxxrawsyscall(SYS_exit_group, code, 0, 0, 0, 0, 0);
  ignored := __pxxrawsyscall(SYS_exit, code, 0, 0, 0, 0, 0);
  { Not reached on Linux. Answering UNSUPPORTED rather than 0 keeps the contract
    the interface states: a caller that gets a value back knows the exit did not
    happen. }
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRandomBytes(buf: Pointer; n: Integer): Integer;
var r: Int64;
begin
  { getrandom(buf, count, flags=0): blocks until the pool is initialised.
    ALL-OR-NOTHING: getrandom may legitimately return fewer bytes than asked
    (it caps at 32MiB, and is interruptible), and a caller seeding a CSPRNG must
    not treat a short fill as success. Reporting only 0-or-negative here keeps
    that decision in one place instead of at each call site.

    THE XTENSA NUMBER WAS MEASURED, NOT RECALLED -- 338, by the method this
    file's xtensa block documents: one syscall per process under
    `qemu-xtensa -strace`, every argument 2147483647 so the call is inert
    whatever it turns out to be. qemu names it `getrandom`, and the same probe
    at 12 names `read`, which is the value this table already had established
    independently. It was previously absent, because random.pas's private copy
    said "CPU_XTENSA (ESP32): no getrandom; use HW RNG register" -- true of
    ESP-IDF, and not of xtensa LINUX, which is this backend's population. The
    arch stood in for the platform, which is the same substitution
    TargetHasSignalRuntime's ruling is about. }
  r := __pxxrawsyscall(SYS_getrandom, Int64(buf), n, 0, 0, 0, 0);
  if r = n then Result := 0
  else if r < 0 then Result := Integer(r)
  else Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendUtimensat(dirFd: Integer; path: PChar;
                             aSec, aNsec, mSec, mNsec: Int64;
                             flags: Integer): Integer;
{ The FULL utimensat(2), which PalBackendUtimes above is one fixed case of:
  AT_FDCWD, no flags, both nanosecond fields zero.

  ONE ENTRY RATHER THAN TWO, because futimens(fd, ts) IS
  utimensat(fd, NULL, ts, 0) -- the kernel says so, and a second PAL entry
  would be a second path to keep in step for no gain. A NIL path is therefore
  not an error here; it is the futimens spelling.

  The nanosecond fields carry UTIME_NOW ($3FFFFFFF) and UTIME_OMIT ($3FFFFFFE)
  as well as real nanoseconds -- that is how `touch -a' leaves mtime alone --
  so they are passed through rather than normalised. NATIVE WORDS, not Int64:
  a 32-bit kernel's timespec is two 32-bit fields and handing it a 16-byte
  struct writes past what it was given. }
var ts: array[0..3] of NativeInt;
begin
{$ifdef CPU_XTENSA}
  Result := PAL_ERR_UNSUPPORTED;
{$else}
  ts[0] := NativeInt(aSec); ts[1] := NativeInt(aNsec);
  ts[2] := NativeInt(mSec); ts[3] := NativeInt(mNsec);
  Result := Integer(__pxxrawsyscall(SYS_utimensat, PtrUInt(dirFd), PtrUInt(path),
                                    PtrUInt(@ts[0]), PtrUInt(flags), 0, 0));
{$endif}
end;

{ MAP_PRIVATE|MAP_ANONYMOUS. 34 ($22) everywhere EXCEPT xtensa, which is one of
  the architectures carrying non-standard MAP_* values: its MAP_ANONYMOUS is
  $800, so the pair is $802 = 2050. Getting this wrong does not fail loudly --
  with 34 the kernel sees MAP_PRIVATE with no ANONYMOUS bit, tries to map fd -1
  and returns EBADF, which becomes a negative "pointer". Measured under
  qemu-xtensa -strace, which decodes the flags as `MAP_PRIVATE|0x20` and names
  the errno. compiler/builtin/builtinheap.pas has carried this arm since hosted
  xtensa first ran; the PAL backend never got it, which is why the heap worked
  on xtensa while PalMmapAnon did not. }
{$ifdef CPU_XTENSA}
const MAP_ANON_PRIV = 2050;
{$else}
const MAP_ANON_PRIV = 34;
{$endif}

function PalBackendMmapAnon(len: Int64): Pointer;
begin
  { mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); 32-bit = mmap2, page-offset 0 }
  Result := Pointer(__pxxrawsyscall(SYS_mmap, 0, len, 3, MAP_ANON_PRIV, -1, 0));
end;

{ Anonymous mmap with an EXPLICIT protection, for callers needing executable
  pages — a JIT writes code then runs it. PalBackendMmapAnon stays RW-only so
  its existing callers are untouched. }
function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
begin
  { 32-bit uses mmap2 with a page offset of 0. See MAP_ANON_PRIV above -- xtensa
    needs 2050, not 34. }
  Result := Pointer(__pxxrawsyscall(SYS_mmap, 0, len, prot, MAP_ANON_PRIV, -1, 0));
end;

function PalBackendMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_mprotect, Int64(addr), len, prot, 0, 0, 0));
end;

function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_munmap, Int64(addr), len, 0, 0, 0, 0));
end;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SOCKET, domain, kind, proto, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_socket, domain, kind, proto, 0, 0, 0));
{$endif}
end;

function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
var one: Integer;
begin
  one := enabled;
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SETSOCKOPT, handle, SOL_SOCKET, SO_REUSEADDR, Int64(@one), 4));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setsockopt, handle, SOL_SOCKET, SO_REUSEADDR,
    Int64(@one), 4, 0));
{$endif}
end;

function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SETSOCKOPT, handle, level, optname, Int64(valPtr), valLen));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_setsockopt, handle, level, optname,
    Int64(valPtr), valLen, 0));
{$endif}
end;

function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
var flags: Integer;
begin
  if enabled <> 0 then flags := O_NONBLOCK else flags := 0;
  Result := Integer(__pxxrawsyscall(SYS_fcntl, handle, F_SETFL, flags, 0, 0, 0));
end;

function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
  FillSockAddrIpv4(@sa[0], hostAddr, port);
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_BIND, handle, Int64(@sa[0]), 16, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_bind, handle, Int64(@sa[0]), 16, 0, 0, 0));
{$endif}
end;

function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
  FillSockAddrIpv4(@sa[0], hostAddr, port);
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_CONNECT, handle, Int64(@sa[0]), 16, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_connect, handle, Int64(@sa[0]), 16, 0, 0, 0));
{$endif}
end;

function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
{ sockaddr_un is 110 bytes:
    0..1     sun_family (AF_UNIX, host order — read as a short)
    2..109   sun_path, 108 bytes, NUL-terminated for a pathname socket

  The whole 110 is passed as the address length, which is what a pathname
  socket wants; the kernel stops at the NUL. A path that does not fit is
  REFUSED rather than truncated — a truncated path is still a valid path, so
  silently shortening it would connect to a different socket than the caller
  named, which is the sort of plausible-wrong-target this codebase does not
  want. The abstract namespace (leading NUL) is deliberately not offered. }
var sa: array[0..109] of Byte; i, n: Integer;
begin
  n := Length(path);
  if n > 107 then
  begin
    Result := PAL_NET_ENAMETOOLONG;
    Exit;
  end;
  for i := 0 to 109 do sa[i] := 0;
  sa[0] := PAL_NET_AF_UNIX and $FF;
  sa[1] := (PAL_NET_AF_UNIX shr 8) and $FF;
  for i := 1 to n do sa[1 + i] := Byte(Ord(path[i]));
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_CONNECT, handle, Int64(@sa[0]), 110, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_connect, handle, Int64(@sa[0]), 110, 0, 0, 0));
{$endif}
end;

{ sockaddr_in6 is 28 bytes:
    0..1   sin6_family (AF_INET6, host order — the kernel reads it as a short)
    2..3   sin6_port      (network order)
    4..7   sin6_flowinfo  (unused here, zero)
    8..23  sin6_addr      (16 bytes, network order = the address as written)
    24..27 sin6_scope_id  (link-local interface index; 0 for global and loopback)
  Note the address bytes are NOT byte-swapped: unlike the IPv4 case, where the
  caller hands us a host-order LongWord, an IPv6 address is already a byte
  string in wire order. }
procedure FillSockAddrIpv6(sa: Pointer; const addr: TPalIn6Addr; port, scopeId: Integer);
var i: Integer;
begin
  for i := 0 to 27 do PB(Pointer(Int64(sa) + i))^ := 0;
  PB(Pointer(Int64(sa) + 0))^ := PAL_NET_AF_INET6 and $FF;
  PB(Pointer(Int64(sa) + 1))^ := (PAL_NET_AF_INET6 shr 8) and $FF;
  PB(Pointer(Int64(sa) + 2))^ := (port shr 8) and $FF;
  PB(Pointer(Int64(sa) + 3))^ := port and $FF;
  for i := 0 to 15 do PB(Pointer(Int64(sa) + 8 + i))^ := addr.Bytes[i];
  PB(Pointer(Int64(sa) + 24))^ := scopeId and $FF;
  PB(Pointer(Int64(sa) + 25))^ := (scopeId shr 8) and $FF;
  PB(Pointer(Int64(sa) + 26))^ := (scopeId shr 16) and $FF;
  PB(Pointer(Int64(sa) + 27))^ := (scopeId shr 24) and $FF;
end;

{ The inverse of FillSockAddrIpv6. Reads back only what a peer address means:
  the 16 address bytes, the wire-order port, and the scope id a link-local
  address needs to be usable at all. }
procedure ParseSockAddrIpv6(sa: Pointer; var addr: TPalIn6Addr;
                            var port, scopeId: Integer);
var i: Integer;
begin
  port := (Integer(PB(Pointer(Int64(sa) + 2))^) shl 8) or Integer(PB(Pointer(Int64(sa) + 3))^);
  for i := 0 to 15 do addr.Bytes[i] := PB(Pointer(Int64(sa) + 8 + i))^;
  scopeId := Integer(PB(Pointer(Int64(sa) + 24))^)
             or (Integer(PB(Pointer(Int64(sa) + 25))^) shl 8)
             or (Integer(PB(Pointer(Int64(sa) + 26))^) shl 16)
             or (Integer(PB(Pointer(Int64(sa) + 27))^) shl 24);
end;

function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr;
                            port, scopeId: Integer): Integer;
var sa: array[0..27] of Byte;
begin
  FillSockAddrIpv6(@sa[0], addr, port, scopeId);
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_BIND, handle, Int64(@sa[0]), 28, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_bind, handle, Int64(@sa[0]), 28, 0, 0, 0));
{$endif}
end;

function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr;
                               port, scopeId: Integer): Integer;
var sa: array[0..27] of Byte;
begin
  FillSockAddrIpv6(@sa[0], addr, port, scopeId);
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_CONNECT, handle, Int64(@sa[0]), 28, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_connect, handle, Int64(@sa[0]), 28, 0, 0, 0));
{$endif}
end;

function PalBackendListen(handle, backlog: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_LISTEN, handle, backlog, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_listen, handle, backlog, 0, 0, 0, 0));
{$endif}
end;

function PalBackendAccept(handle: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_ACCEPT4, handle, 0, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_accept4, handle, 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := __pxxrawsyscall(SYS_read, handle, Int64(buf), len, 0, 0, 0);
end;

{ sendto(2) with a nil destination rather than write(2): write has no flags
  argument to carry MSG_NOSIGNAL, and without it a closed peer kills the process.
  Safe because every caller of PalSend is a socket by contract -- fpSend, the
  net/asyncnet/dns senders, and the C send() veneer in pxxcio. }
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
{$ifdef CPU_I386}
  Result := SockCall6(SC_SENDTO, handle, Int64(buf), len, MSG_NOSIGNAL, 0, 0);
{$else}
  Result := __pxxrawsyscall(SYS_sendto, handle, Int64(buf), len, MSG_NOSIGNAL, 0, 0);
{$endif}
end;

function PalBackendShutdown(handle, how: Integer): Integer;
begin
{$ifdef CPU_I386}
  Result := Integer(SockCall(SC_SHUTDOWN, handle, how, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_shutdown, handle, how, 0, 0, 0, 0));
{$endif}
end;

function PalBackendSocketClose(handle: Integer): Integer;
begin
  Result := PalBackendClose(handle);
end;

function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
var sa: array[0..15] of Byte;
begin
  FillSockAddrIpv4(@sa[0], hostAddr, port);
{$ifdef CPU_I386}
  Result := SockCall6(SC_SENDTO, handle, Int64(buf), len, MSG_NOSIGNAL, Int64(@sa[0]), 16);
{$else}
  Result := __pxxrawsyscall(SYS_sendto, handle, Int64(buf), len, MSG_NOSIGNAL, Int64(@sa[0]), 16);
{$endif}
end;

function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  Result := SockCall6(SC_RECVFROM, handle, Int64(buf), len, 0, Int64(@sa[0]), Int64(@addrlen));
{$else}
  Result := __pxxrawsyscall(SYS_recvfrom, handle, Int64(buf), len, 0, Int64(@sa[0]), Int64(@addrlen));
{$endif}
  outAddr := 0;
  outPort := 0;
  if Result >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
end;

function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer;
                              const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
var sa: array[0..27] of Byte;
begin
  FillSockAddrIpv6(@sa[0], addr, port, scopeId);
{$ifdef CPU_I386}
  Result := SockCall6(SC_SENDTO, handle, Int64(buf), len, MSG_NOSIGNAL, Int64(@sa[0]), 28);
{$else}
  Result := __pxxrawsyscall(SYS_sendto, handle, Int64(buf), len, MSG_NOSIGNAL, Int64(@sa[0]), 28);
{$endif}
end;

function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer;
                                var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
var
  sa: array[0..27] of Byte;
  addrlen: Integer;
  i: Integer;
begin
  for i := 0 to 27 do sa[i] := 0;
  addrlen := 28;
{$ifdef CPU_I386}
  Result := SockCall6(SC_RECVFROM, handle, Int64(buf), len, 0, Int64(@sa[0]), Int64(@addrlen));
{$else}
  Result := __pxxrawsyscall(SYS_recvfrom, handle, Int64(buf), len, 0, Int64(@sa[0]), Int64(@addrlen));
{$endif}
  for i := 0 to 15 do outAddr.Bytes[i] := 0;
  outPort := 0;
  outScopeId := 0;
  if Result >= 0 then
    ParseSockAddrIpv6(@sa[0], outAddr, outPort, outScopeId);
end;

type
  TTimeSpec = record
    Sec: NativeInt;
    Nsec: NativeInt;
  end;

{ Readiness poll via ppoll (available on every PAL arch; aarch64 lacks legacy
  poll). pollfd is int fd then short events then short revents; we pack the
  second word as events or revents-shifted-16 on little-endian targets. Returns
  the revents bitmask when positive, 0 on timeout, or -errno. }
function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
var
  pfd: array[0..1] of Integer;
  ts: TTimeSpec;
  tsp: Pointer;
  res: Int64;
begin
  pfd[0] := handle;
  pfd[1] := events and $FFFF;
  if timeoutMs < 0 then
    tsp := nil
  else
  begin
    ts.Sec := timeoutMs div 1000;
    ts.Nsec := (timeoutMs mod 1000) * 1000000;
    tsp := @ts;
  end;
  res := __pxxrawsyscall(SYS_ppoll, Int64(@pfd[0]), 1, Int64(tsp), 0, 0, 0);
  if res < 0 then
    Result := Integer(res)
  else if res = 0 then
    Result := 0
  else
    Result := (pfd[1] shr 16) and $FFFF;
end;

{ Set-shaped ppoll. The caller's array IS the kernel's: C's `struct pollfd` is
  int fd then two shorts, which is exactly the 8-byte pair PalBackendPoll packs
  by hand for one entry, so nothing is copied or repacked and revents land back
  in the caller's own memory. Returns the ready count (not a revents mask —
  with a set there is no single mask to return), 0 on timeout, -errno on error. }
function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
var
  ts: TTimeSpec;
  tsp: Pointer;
  res: Int64;
begin
  if nfds < 0 then
  begin
    Result := -22;                 { EINVAL }
    Exit;
  end;
  if timeoutMs < 0 then
    tsp := nil
  else
  begin
    ts.Sec := timeoutMs div 1000;
    ts.Nsec := (timeoutMs mod 1000) * 1000000;
    tsp := @ts;
  end;
  res := __pxxrawsyscall(SYS_ppoll, Int64(fds), nfds, Int64(tsp), 0, 0, 0);
  Result := Integer(res);
end;

{ Pending socket error via getsockopt(SO_ERROR): the canonical way to read the
  result of a non-blocking connect after poll reports writable. SO_ERROR is a
  positive errno that is cleared on read; we report 0 (clean) or -errno. If the
  getsockopt call itself fails, its own -errno is returned. }
function PalBackendGetSockError(handle: Integer): Integer;
var
  err, optlen: Integer;
  rc: Int64;
begin
  err := 0;
  optlen := 4;
{$ifdef CPU_I386}
  rc := SockCall(SC_GETSOCKOPT, handle, SOL_SOCKET, SO_ERROR, Int64(@err), Int64(@optlen));
{$else}
  rc := __pxxrawsyscall(SYS_getsockopt, handle, SOL_SOCKET, SO_ERROR, Int64(@err), Int64(@optlen), 0);
{$endif}
  if rc < 0 then
    Result := Integer(rc)
  else
    Result := -err;
end;

function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Int64;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  rc := SockCall(SC_GETSOCKNAME, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0);
{$else}
  rc := __pxxrawsyscall(SYS_getsockname, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0, 0);
{$endif}
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := Integer(rc);
end;

function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr;
                              var outPort, outScopeId: Integer): Integer;
var
  sa: array[0..27] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Int64;
begin
  for i := 0 to 27 do sa[i] := 0;
  addrlen := 28;
{$ifdef CPU_I386}
  rc := SockCall(SC_ACCEPT4, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0);
{$else}
  rc := __pxxrawsyscall(SYS_accept4, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0, 0);
{$endif}
  for i := 0 to 15 do outAddr.Bytes[i] := 0;
  outPort := 0;
  outScopeId := 0;
  if rc >= 0 then
    ParseSockAddrIpv6(@sa[0], outAddr, outPort, outScopeId);
  Result := Integer(rc);
end;

function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Int64;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  rc := SockCall(SC_GETPEERNAME, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0);
{$else}
  rc := __pxxrawsyscall(SYS_getpeername, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0, 0);
{$endif}
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := Integer(rc);
end;

function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
var rc: Int64;
begin
{$ifdef CPU_I386}
  rc := SockCall(SC_GETSOCKOPT, handle, level, optname, Int64(valPtr), Int64(lenPtr));
{$else}
  rc := __pxxrawsyscall(SYS_getsockopt, handle, level, optname, Int64(valPtr), Int64(lenPtr), 0);
{$endif}
  Result := Integer(rc);
end;

function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_ioctl, handle, cmd, Int64(argp), 0, 0, 0));
end;

function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Int64;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
{$ifdef CPU_I386}
  rc := SockCall(SC_ACCEPT4, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0);
{$else}
  rc := __pxxrawsyscall(SYS_accept4, handle, Int64(@sa[0]), Int64(@addrlen), 0, 0, 0);
{$endif}
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := Integer(rc);
end;

function PalBackendMonotonicMillis: Int64;
var
  ts: TTimeSpec;
  res: Int64;
begin
  res := __pxxrawsyscall(SYS_clock_gettime, 1, Int64(@ts), 0, 0, 0, 0); { CLOCK_MONOTONIC = 1 }
  if res = 0 then
    Result := (Int64(ts.Sec) * 1000) + (Int64(ts.Nsec) div 1000000)
  else
    Result := 0;
end;

procedure PalBackendYield;
begin
end;

{ WAS CALLED PalBackendVfork, AND THE BODY WAS NEVER A VFORK. Both arms give the
  child its OWN copy-on-write address space: SYS_fork directly, or clone with
  SIGCHLD and no CLONE_VM, which is precisely what fork(2) is. Nothing shares the
  parent's memory and nothing constrains the child to exec-or-_exit.

  The old name cost a real conclusion, which is why it is being corrected rather
  than left alone. lib/crtl/src/unistd.c reasoned FROM THE NAME -- "the PAL has
  PalVfork, and vfork is NOT fork, so wiring fork to it would be a silent
  corruption" -- and left fork() as an ENOSYS stub on that basis. The comment
  even ends by telling the reader to MEASURE the PAL before believing a line
  that says an entry is missing, which is exactly the step it skipped. busybox
  ash then failed with `can't fork', against a PAL that had had fork all along.
  An 80%-accurate name is worse than no name: the half that reads true is what
  stops you looking.

  PalVforkAndExec keeps its name for now -- it has real callers in
  subprocess.pas -- but its body forks too, and says so at its own head. }
function PalBackendFork: Integer;
begin
{$ifdef PAL_GENERIC_SYSCALLS}
  Result := Integer(__pxxrawsyscall(SYS_clone, $11, 0, 0, 0, 0, 0)); { SIGCHLD only -> fork (own COW address space) }
{$else}
  Result := Integer(__pxxrawsyscall(SYS_fork, 0, 0, 0, 0, 0, 0));
{$endif}
end;

function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_execve, Int64(path), Int64(argv), Int64(envp), 0, 0, 0));
end;

function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_pipe2, Int64(@pipefd[0]), flags, 0, 0, 0, 0));
end;

function PalBackendDup2(oldFd, newFd: Integer): Integer;
begin
{$ifdef PAL_GENERIC_SYSCALLS}
  Result := Integer(__pxxrawsyscall(SYS_dup3, oldFd, newFd, 0, 0, 0, 0));
{$else}
  Result := Integer(__pxxrawsyscall(SYS_dup2, oldFd, newFd, 0, 0, 0, 0));
{$endif}
end;

function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_wait4, pid, Int64(wstatus), options, Int64(rusage), 0, 0));
end;

function PalBackendKill(pid, sig: Integer): Integer;
begin
  Result := Integer(__pxxrawsyscall(SYS_kill, pid, sig, 0, 0, 0, 0));
end;

function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
var
  pid: Integer;
  res: Integer;
begin
{ Real fork (not vfork): the child gets its own copy-on-write address space, so
  it can safely run this Pascal child path (dup2/close/execve) without clobbering
  the parent's stack -- the shared-VM vfork hazard the ticket warned about. }
{$ifdef PAL_GENERIC_SYSCALLS}
  pid := Integer(__pxxrawsyscall(SYS_clone, $11, 0, 0, 0, 0, 0)); { SIGCHLD only -> fork }
{$else}
  pid := Integer(__pxxrawsyscall(SYS_fork, 0, 0, 0, 0, 0, 0));
{$endif}

  if pid = 0 then
  begin
    { Child process }
    if stdinReadFd <> -1 then
    begin
{$ifdef PAL_GENERIC_SYSCALLS}
      res := Integer(__pxxrawsyscall(SYS_dup3, stdinReadFd, 0, 0, 0, 0, 0));
{$else}
      res := Integer(__pxxrawsyscall(SYS_dup2, stdinReadFd, 0, 0, 0, 0, 0));
{$endif}
      res := Integer(__pxxrawsyscall(SYS_close, stdinReadFd, 0, 0, 0, 0, 0));
      res := Integer(__pxxrawsyscall(SYS_close, stdinWriteFd, 0, 0, 0, 0, 0));
    end;

    if stdoutWriteFd <> -1 then
    begin
{$ifdef PAL_GENERIC_SYSCALLS}
      res := Integer(__pxxrawsyscall(SYS_dup3, stdoutWriteFd, 1, 0, 0, 0, 0));
{$else}
      res := Integer(__pxxrawsyscall(SYS_dup2, stdoutWriteFd, 1, 0, 0, 0, 0));
{$endif}
      res := Integer(__pxxrawsyscall(SYS_close, stdoutReadFd, 0, 0, 0, 0, 0));
      res := Integer(__pxxrawsyscall(SYS_close, stdoutWriteFd, 0, 0, 0, 0, 0));
    end;

    res := Integer(__pxxrawsyscall(SYS_execve, Int64(path), Int64(argv), Int64(envp), 0, 0, 0));

    { If execve fails, exit. Through the per-arch SYS_exit constant, never a
      literal: this was four {$ifdef} arms holding 60 / 1 / 93 / 1, and the 93
      was keyed on PAL_GENERIC_SYSCALLS -- which means a calling SHAPE (clone,
      dup3, direct sockets), not a numbering. It happened to be right because
      the only two arches with that shape also shared the asm-generic table.
      xtensa has the shape and its own numbers, where 93 is `socket`: the child
      would open a socket, fall out of this block still being the child, and
      hand its caller pid 0 to read as "I am the parent". Every arch keeps the
      exact number it had, so the five existing targets are unchanged. }
    res := Integer(__pxxrawsyscall(SYS_exit, 127, 0, 0, 0, 0, 0));
  end;

  Result := pid;
end;

end.
