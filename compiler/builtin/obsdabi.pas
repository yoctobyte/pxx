unit obsdabi;

{ The Linux syscall ABI on an OpenBSD kernel -- EXPERIMENTAL (--os=openbsd).
  The same design as fbsdabi.pas (read its header first): every kernel entry
  pxx emits is written against Linux, funnels through the shared thunk, and
  arrives here with the Linux number and arguments; this unit maps the
  number, rewrites what differs, makes the real OpenBSD call from ObRawA, and
  maps OpenBSD's errno back to Linux's.

  WHAT IS OpenBSD-SPECIFIC
  - pinsyscalls: OpenBSD kills a syscall made from an address its
    PT_OPENBSD_SYSCALLS table does not pin for that number. The ELF writer
    (ObsdPinVA) pins EVERY number to the one `syscall` in ObRawA, so all
    kernel entry must come through here -- a raw `syscall` anywhere else dies
    with SIGABRT and a "PINS" line in ktrace.
  - TLS: OpenBSD userland cannot set the GS base; __set_tcb sets FS. Under
    --os=openbsd the compiler emits pxx's TLS accesses as fs: (TlsSegPrefix),
    and arch_prctl(ARCH_SET_GS) arrives here and becomes __set_tcb.
  - System call numbers are not a stable ABI across OpenBSD releases; these
    are 8.0's, and a binary is tied to the release it was built against.

  CONSTANTS ARE MEASURED: syscall numbers, errno, flags and clocks from
  OpenBSD 8.0 amd64's /usr/include; struct offsets from offsetof() compiled
  on that system (2026-11-12).

  CONTEXT RULES are fbsdabi's: no managed types, no heap, no exceptions, no
  RTL calls; ObRawA is the only kernel entry.

  DONE: files, directories, memory, time, process basics, TLS, uname,
  rlimits, /proc/self/environ and /proc/self/exe, isatty, signals (handlers,
  masks, the alt stack, kill/tgkill, itimers), threads (clone -> __tfork,
  thread exit, futex), sockets, ppoll/pselect6, epoll (over kqueue).
  termios and the tty ioctls, timerfd (over kqueue). NOT YET: eventfd, ptys.
  Anything unmapped answers -ENOSYS. }

interface

function PXXObsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;

implementation

const
  LX_ENOENT = 2;
  LX_EINVAL = 22;
  LX_ENOMEM = 12;
  LX_ENOTTY = 25;
  LX_ENOSYS = 38;

  { OpenBSD 8.0 amd64 syscall numbers (sys/syscall.h) }
  OB_EXIT = 1; OB_FORK = 2; OB_READ = 3; OB_WRITE = 4; OB_CLOSE = 6;
  OB_GETENTROPY = 7; OB_LINK = 9; OB_UNLINK = 10; OB_WAIT4 = 11; OB_CHDIR = 12;
  OB_FCHDIR = 13; OB_CHMOD = 15; OB_CHOWN = 16; OB_GETRUSAGE = 19;
  OB_GETPID = 20; OB_SETUID = 23; OB_GETUID = 24; OB_GETEUID = 25;
  OB_GETPPID = 39; OB_DUP = 41; OB_FSTATAT = 42; OB_GETEGID = 43;
  OB_GETGID = 47; OB_MMAP = 49; OB_FSTAT = 53; OB_IOCTL = 54; OB_SYMLINK = 57;
  OB_READLINK = 58; OB_EXECVE = 59; OB_UMASK = 60; OB_GETTIMEOFDAY = 67;
  OB_SELECT = 71; OB_MUNMAP = 73; OB_MPROTECT = 74; OB_MADVISE = 75;
  OB_GETPGRP = 81; OB_SETPGID = 82; OB_UTIMENSAT = 84; OB_CLOCK_GETTIME = 87;
  OB_CLOCK_GETRES = 89; OB_DUP2 = 90; OB_NANOSLEEP = 91; OB_FCNTL = 92;
  OB_FSYNC = 95; OB_SETPRIORITY = 96; OB_GETDENTS = 99; OB_GETPRIORITY = 100;
  OB_PIPE2 = 101; OB_DUP3 = 102; OB_KILL = 122; OB_FCHOWN = 123;
  OB_FCHMOD = 124; OB_READV = 120; OB_WRITEV = 121; OB_RENAME = 128;
  OB_FLOCK = 131; OB_MKDIR = 136; OB_RMDIR = 137; OB_SETSID = 147;
  OB_LSEEK = 166; OB_TRUNCATE = 167; OB_FTRUNCATE = 168; OB_PREAD = 169;
  OB_PWRITE = 170; OB_PREADV = 171; OB_PWRITEV = 172; OB_SETGID = 181;
  OB_GETRLIMIT = 194; OB_SETRLIMIT = 195; OB_SYSCTL = 202; OB_GETPGID = 207;
  OB_POLL = 252; OB_LCHOWN = 254; OB_GETSID = 255; OB_SCHED_YIELD = 298;
  OB_GETTHRID = 299; OB_GETCWD = 304; OB_FACCESSAT = 313; OB_FCHMODAT = 314;
  OB_FCHOWNAT = 315; OB_LINKAT = 317; OB_MKDIRAT = 318; OB_OPENAT = 321;
  OB_READLINKAT = 322; OB_RENAMEAT = 323; OB_SYMLINKAT = 324; OB_UNLINKAT = 325;
  OB_SET_TCB = 329; OB_GET_TCB = 330;
  OB_SIGACTION = 46; OB_SIGPROCMASK = 48; OB_SIGPENDING = 52;
  OB_GETITIMER = 70; OB_SETITIMER = 69; OB_SIGSUSPEND = 111; OB_THRKILL = 119;
  OB_SIGALTSTACK = 288;
  OB_TFORK = 8; OB_FUTEX = 83; OB_THREXIT = 302;
  OB_PPOLL = 109; OB_PSELECT = 110;
  OB_MKNOD = 14; OB_SYNC = 36; OB_STATFS = 63; OB_FSTATFS = 64; OB_UTIMES = 76;
  OB_GETGROUPS = 79; OB_SETGROUPS = 80; OB_FUTIMENS = 85; OB_CLOCK_SETTIME = 88;
  OB_SETREUID = 126; OB_SETREGID = 127; OB_GETTHRNAME = 142; OB_SETTHRNAME = 143;
  OB_MLOCK = 203; OB_MUNLOCK = 204; OB_MLOCKALL = 271; OB_MUNLOCKALL = 272;
  OB_GETRESUID = 281; OB_SETRESUID = 282; OB_GETRESGID = 283; OB_SETRESGID = 284;
  OB_THRSIGDIVERT = 303; OB_MKNODAT = 320;

  OB_AT_FDCWD = -100;             { same value as Linux }
  OB_AT_EACCESS = $01; OB_AT_SYMLINK_NOFOLLOW = $02; OB_AT_SYMLINK_FOLLOW = $04;
  OB_AT_REMOVEDIR = $08;

  OB_MAP_FIXED = $10; OB_MAP_ANON = $1000; OB_MAP_STACK = $4000;
  OB_RLIM_INFINITY = $7FFFFFFFFFFFFFFF;

  OB_TIOCGETA = $402C7413; OB_TIOCGWINSZ = $40087468;
  OB_FIONREAD = $4004667F; OB_FIONBIO = $8004667E;

  { OpenBSD errno 35..95 -> Linux errno. 1..34 are the same on both. }
  ErrMap: array[35..95] of Integer = (
    11, 115, 114, 88, 89, 90, 91, 92, 93, 94,      { 35 EAGAIN .. 44 ESOCKTNOSUPPORT }
    95, 96, 97, 98, 99, 100, 101, 102, 103, 104,   { 45 EOPNOTSUPP .. 54 ECONNRESET }
    105, 106, 107, 108, 109, 110, 111, 40, 36, 112, { 55 ENOBUFS .. 64 EHOSTDOWN }
    113, 39, 11, 87, 122, 116, 66, 22, 22, 22,     { 65 EHOSTUNREACH .. 74 EPROGUNAVAIL }
    22, 22, 37, 38, 22, 13, 13, 22, 61, 84,        { 75 EPROGMISMATCH .. 84 EILSEQ }
    123, 124, 75, 125, 43, 42, 95, 74, 131, 130,   { 85 ENOMEDIUM .. 94 EOWNERDEAD }
    71);                                           { 95 EPROTO }

  { Linux signal 0..31 -> OpenBSD. 0 = no OpenBSD equivalent. }
  SigMap: array[0..31] of Integer = (
    0, 1, 2, 3, 4, 5, 6, 10, 8, 9, 30, 11, 31, 13, 14, 15,
    0, 20, 19, 17, 18, 21, 22, 16, 24, 25, 26, 27, 28, 23, 0, 12);

  { Linux RLIMIT_* 0..9 (CPU FSIZE DATA STACK CORE RSS NPROC NOFILE MEMLOCK AS)
    -> OpenBSD; -1 = none (RLIMIT_AS). }
  RlimMap: array[0..9] of Integer = (0, 1, 2, 3, 4, 5, 7, 8, 6, -1);

  BRK_RESERVE = Int64(1024) * 1024 * 1024;   { PROT_NONE address space, grown by mprotect }

var
  ObBrkBase, ObBrkCur, ObBrkTop: Int64;
  ObTmpSeq: Int64;
  ObMainTid: Int64;          { the thread that first called clone; 0 = no threads yet }
  ObExitStack: Int64;        { the shared thread-exit stack (MAP_STACK) }
  ObExitLock: Integer;       { its lock; __threxit's notdead clears it }

const
  OB_EXIT_STACK_SIZE = 16384;
  { The TLS slot the clone stub leaves free for the child's ctid pointer on
    x86-64: defs.inc's TLS_SLOT_FS_ENTRY (14), i386's fs entry slot, never
    written on x86-64. fbsdabi uses the same slot for the same purpose. }
  OB_TLS_SLOT_CTID = 14;

{$ifdef CPU_AARCH64}
{ OpenBSD/arm64 (measured from sys/arch/arm64/arm64/syscall.c): the number
  in x8, arguments x0..x7, C set = error with the positive errno in x0. The
  kernel resumes 8 bytes past the svc -- libc's `dsb nsh; isb` speculation
  barrier -- so the same two words follow every svc here (on ERESTART it
  backs up 12, onto the svc). Only x0 comes back: no second result
  register, so a[7] stays 0 (a fork child gets x0 = 0 directly). }
function ObRawA(args: Pointer): Int64; assembler;
asm
  mov x9, x0
  ldr x8, [x9]
  ldr x0, [x9, 8]
  ldr x1, [x9, 16]
  ldr x2, [x9, 24]
  ldr x3, [x9, 32]
  ldr x4, [x9, 40]
  ldr x5, [x9, 48]
  svc 0
  inst $D503379F
  inst $D5033FDF
  mov x10, 0
  b.cc obrawok
  mov x10, 1
  sub x0, xzr, x0
obrawok:
  str x10, [x9, 64]
end;

{ __tfork(param, psize) with the child sent to cont, as the x86-64 one. The
  child resumes past the barrier with the parent's registers (x9 = cont),
  x0 = 0, sp = tf_stack and tpidr_el0 = tf_tcb. }
function ObTforkA(param, psize, cont: Int64): Int64; assembler;
asm
  mov x9, x2
  mov x8, 8
  svc 0
  inst $D503379F
  inst $D5033FDF
  b.cs obtf_fail
  cbz x0, obtf_child
  b obtf_done
obtf_child:
  br x9
obtf_fail:
  sub x0, xzr, x0
obtf_done:
end;

{ The x86-64 routine's steps (read it): the spin lock on the shared exit
  stack, then clear and wake through ObRawA by address, then __threxit with
  the lock as its notdead word. x19..x22 are never given back: this does not
  return. }
procedure ObThreadExitA(ctid, lock, top, raw: Int64); assembler;
asm
  mov x19, x0
  mov x20, x1
  mov x21, x2
  mov x22, x3
  mov w10, 1
obte_spin:
  inst $885FFE8B
  cbnz w11, obte_spin
  inst $880C7E8A
  cbnz w12, obte_spin
  inst $910002BF
  str wzr, [x19]
  inst $D10143FF
  mov x10, 83
  str x10, [sp]
  str x19, [sp, 8]
  mov x10, 2
  str x10, [sp, 16]
  mov x10, 2147483647
  str x10, [sp, 24]
  str xzr, [sp, 32]
  str xzr, [sp, 40]
  str xzr, [sp, 48]
  inst $910003E0
  blr x22
  mov x10, 83
  str x10, [sp]
  str x19, [sp, 8]
  mov x10, 130
  str x10, [sp, 16]
  mov x10, 2147483647
  str x10, [sp, 24]
  str xzr, [sp, 32]
  str xzr, [sp, 40]
  str xzr, [sp, 48]
  inst $910003E0
  blr x22
  mov x10, 302
  str x10, [sp]
  str x20, [sp, 8]
  inst $910003E0
  blr x22
end;
{ The inst words: dsb nsh; isb; ldaxr w11, [x20]; stxr w12, w10, [x20];
  mov sp, x21; sub sp, sp, #80; mov x0, sp. }
{$else}
{$ifdef PXX_OBSD_LIBC}
{ --os=openbsd --rtl-libc: no kernel entry in this program at all. Each
  OpenBSD call goes to libc's wrapper of the same name (OpenBSD 8.0's
  libc.so.104.0; ld.so pins libc's syscalls, so pinsyscalls is satisfied by
  construction). Every wrapper takes the raw call's arguments, except the
  three signal-mask calls, which take pointers in libc and values in the
  kernel; ObSys converts those. Threads are refused at compile time for now:
  OpenBSD threads in a libc program are libc's, not __tfork's. }
function Lc_exit(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name '_exit';
function Lc_fork(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fork';
function Lc_read(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'read';
function Lc_write(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'write';
function Lc_close(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'close';
function Lc_getentropy(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getentropy';
function Lc_link(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'link';
function Lc_unlink(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'unlink';
function Lc_wait4(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'wait4';
function Lc_chdir(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'chdir';
function Lc_fchdir(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fchdir';
function Lc_mknod(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mknod';
function Lc_chmod(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'chmod';
function Lc_chown(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'chown';
function Lc_getrusage(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getrusage';
function Lc_getpid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getpid';
function Lc_setuid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setuid';
function Lc_getuid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getuid';
function Lc_geteuid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'geteuid';
function Lc_recvmsg(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'recvmsg';
function Lc_sendmsg(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sendmsg';
function Lc_recvfrom(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'recvfrom';
function Lc_accept(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'accept';
function Lc_getpeername(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getpeername';
function Lc_getsockname(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getsockname';
function Lc_sync(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sync';
function Lc_getppid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getppid';
function Lc_dup(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'dup';
function Lc_fstatat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fstatat';
function Lc_getegid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getegid';
function Lc_sigaction(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sigaction';
function Lc_getgid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getgid';
function Lc_sigprocmask(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sigprocmask';
function Lc_mmap(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mmap';
function Lc_sigpending(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sigpending';
function Lc_fstat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fstat';
function Lc_ioctl(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'ioctl';
function Lc_symlink(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'symlink';
function Lc_readlink(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'readlink';
function Lc_execve(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'execve';
function Lc_umask(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'umask';
function Lc_statfs(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'statfs';
function Lc_fstatfs(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fstatfs';
function Lc_gettimeofday(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'gettimeofday';
function Lc_setitimer(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setitimer';
function Lc_getitimer(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getitimer';
function Lc_select(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'select';
function Lc_kevent(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'kevent';
function Lc_munmap(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'munmap';
function Lc_mprotect(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mprotect';
function Lc_madvise(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'madvise';
function Lc_utimes(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'utimes';
function Lc_getgroups(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getgroups';
function Lc_setgroups(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setgroups';
function Lc_getpgrp(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getpgrp';
function Lc_setpgid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setpgid';
function Lc_futex(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'futex';
function Lc_utimensat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'utimensat';
function Lc_futimens(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'futimens';
function Lc_clock_gettime(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'clock_gettime';
function Lc_clock_settime(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'clock_settime';
function Lc_clock_getres(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'clock_getres';
function Lc_dup2(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'dup2';
function Lc_nanosleep(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'nanosleep';
function Lc_fcntl(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fcntl';
function Lc_accept4(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'accept4';
function Lc_fsync(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fsync';
function Lc_setpriority(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setpriority';
function Lc_socket(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'socket';
function Lc_connect(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'connect';
function Lc_getdents(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getdents';
function Lc_getpriority(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getpriority';
function Lc_pipe2(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'pipe2';
function Lc_dup3(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'dup3';
function Lc_bind(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'bind';
function Lc_setsockopt(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setsockopt';
function Lc_listen(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'listen';
function Lc_ppoll(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'ppoll';
function Lc_pselect(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'pselect';
function Lc_sigsuspend(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sigsuspend';
function Lc_getsockopt(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getsockopt';
function Lc_thrkill(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'thrkill';
function Lc_readv(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'readv';
function Lc_writev(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'writev';
function Lc_kill(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'kill';
function Lc_fchown(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fchown';
function Lc_fchmod(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fchmod';
function Lc_setreuid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setreuid';
function Lc_setregid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setregid';
function Lc_rename(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'rename';
function Lc_flock(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'flock';
function Lc_sendto(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sendto';
function Lc_shutdown(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'shutdown';
function Lc_socketpair(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'socketpair';
function Lc_mkdir(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mkdir';
function Lc_rmdir(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'rmdir';
function Lc_getthrname(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getthrname';
function Lc_setthrname(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setthrname';
function Lc_setsid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setsid';
function Lc_lseek(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'lseek';
function Lc_truncate(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'truncate';
function Lc_ftruncate(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'ftruncate';
function Lc_pread(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'pread';
function Lc_pwrite(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'pwrite';
function Lc_preadv(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'preadv';
function Lc_pwritev(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'pwritev';
function Lc_setgid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setgid';
function Lc_getrlimit(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getrlimit';
function Lc_setrlimit(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setrlimit';
function Lc_sysctl(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sysctl';
function Lc_mlock(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mlock';
function Lc_munlock(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'munlock';
function Lc_getpgid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getpgid';
function Lc_poll(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'poll';
function Lc_lchown(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'lchown';
function Lc_getsid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getsid';
function Lc_kqueue(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'kqueue';
function Lc_mlockall(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mlockall';
function Lc_munlockall(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'munlockall';
function Lc_getresuid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getresuid';
function Lc_setresuid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setresuid';
function Lc_getresgid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getresgid';
function Lc_setresgid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'setresgid';
function Lc_sigaltstack(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sigaltstack';
function Lc_sched_yield(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'sched_yield';
function Lc_getthrid(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getthrid';
function Lc_threxit(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name '__threxit';
function Lc_thrsigdivert(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name '__thrsigdivert';
function Lc_getcwd(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'getcwd';
function Lc_faccessat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'faccessat';
function Lc_fchmodat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fchmodat';
function Lc_fchownat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'fchownat';
function Lc_linkat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'linkat';
function Lc_mkdirat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mkdirat';
function Lc_mknodat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'mknodat';
function Lc_openat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'openat';
function Lc_readlinkat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'readlinkat';
function Lc_renameat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'renameat';
function Lc_symlinkat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'symlinkat';
function Lc_unlinkat(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name 'unlinkat';
function Lc_set_tcb(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name '__set_tcb';
function Lc_get_tcb(a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl; external 'libc.so.104.0' name '__get_tcb';
function Lc_errno: Int64; cdecl; external 'libc.so.104.0' name '__errno';

function Lc_tfork_thread(param, psize, fn, arg: Int64): Int64; cdecl; external 'libc.so.104.0' name '__tfork_thread';
function Lc_dl_allocate_tib(extra: Int64): Int64; cdecl; external 'libc.so.104.0' name '_dl_allocate_tib';

function ObSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; forward;

{ The bytes ld.so reserves below fs for the pxx block: defs.inc's
  TlsLibcSpan, which the compiler's TLS displacements use. }
function ObTlsSpan: Int64;
begin
  Result := (__pxxTlsBlockSize + 16 + 15) and (not Int64(15));
end;

{ The calling thread's pxx block: its PT_TLS area, right below libc's TCB. }
function ObMyBlock: Int64;
begin
  Result := Lc_get_tcb(0, 0, 0, 0, 0, 0) - ObTlsSpan;
end;

{ The child's first code. __tfork_thread calls fn(arg) on the new stack;
  a pxx clone child must instead resume at the stub's child entry with rsp =
  the stage area, so arg is a record {resume, stage} in the 16-byte scratch
  past the child's block (see ObTforkA), read whatever frame this has. }
function ObChildTramp(rec: Int64): Int64; assembler;
{$asmMode intel}
asm
  mov rdi, rec
  mov rax, [rdi]
  mov rsp, [rdi+8]
  push rax
  ret
end;

{ __tfork with the child sent to cont, as the raw ObTforkA does, through
  libc's __tfork_thread. tf_tcb (param[0]) is a thread block from ld.so's
  _dl_allocate_tib, set up by ObClone; the record for ObChildTramp goes in
  its pxx block's scratch, which nothing else uses on a child. }
function ObTforkA(param, psize, cont: Int64): Int64;
var rec: Int64; r: Int64; e: PInteger;
begin
  rec := PInt64(param)^ - ObTlsSpan + __pxxTlsBlockSize;
  PInt64(rec)^ := cont;
  PInt64(rec + 8)^ := PInt64(param + 16)^;
  e := PInteger(Lc_errno);
  e^ := 0;
  r := Int64(LongInt(Lc_tfork_thread(param, psize, Int64(@ObChildTramp), rec)));
  if (r = -1) and (e^ <> 0) then r := -e^;
  Result := r;
end;

{ ObThreadExitA's kernel entry, by address: [nr, a0..a5]. }
function ObRawA(args: Pointer): Int64;
var a: PInt64;
begin
  a := PInt64(args);
  Result := ObSys(a[0], a[1], a[2], a[3], a[4], a[5], a[6]);
end;
{$else}
{ The ONE kernel entry, and the one address the pin table names. args ->
  [nr, a0..a5, rdx-out, cf-out]. OpenBSD reports an error with CF set and the
  positive errno in rax; the sbb/xor/sub trio negates rax exactly then. }
function ObRawA(args: Pointer): Int64; assembler;
{$asmMode intel}
asm
  push r12
  mov r12, args
  mov rax, [r12]
  mov rdi, [r12+8]
  mov rsi, [r12+16]
  mov rdx, [r12+24]
  mov r10, [r12+32]
  mov r8, [r12+40]
  mov r9, [r12+48]
  syscall
  mov [r12+56], rdx
  sbb rcx, rcx
  mov [r12+64], rcx
  xor rax, rcx
  sub rax, rcx
  pop r12
end;

{ __tfork(param, psize), with the child sent to cont. This is the one other
  syscall site the pin table names (SYS___tfork only, see ObsdPinVA): the
  child resumes after the instruction like a clone child, on its new stack,
  so it cannot come back through ObRawA's frame. r8 survives the syscall into
  the child (the kernel copies the parent's registers), and the child jumps
  to cont -- the clone stub's child entry -- with rsp = tf_stack. The parent
  gets the tid, or -errno. }
function ObTforkA(param, psize, cont: Int64): Int64; assembler;
{$asmMode intel}
asm
  mov r8, cont
  mov rdi, param
  mov rsi, psize
  mov eax, 8
  syscall
  jb obtf_fail
  test eax, eax
  jz obtf_child
  jmp obtf_done
obtf_child:
  push r8                 { jmp r8: the assembler takes label targets only }
  ret
obtf_fail:
  neg rax
obtf_done:
end;

{$endif}

{ The last steps of a non-main thread's exit: the CLONE_CHILD_CLEARTID work
  Linux's kernel does, which OpenBSD's does not (its __threxit clears a word
  but wakes nobody). The moment the tid word is zero a joiner may unmap this
  thread's stack, so the clear and the wakes run on a shared exit stack
  (MAP_STACK, mapped by the translator) taken under a spin lock -- and the
  lock word is __threxit's `notdead`, so the KERNEL releases it once this
  thread is past using that stack. Wakes go to both futex queues (a joiner may
  wait private or shared), through ObRawA called by address: registers and
  the exit stack only. Does not return. }
procedure ObThreadExitA(ctid, lock, top, raw: Int64); assembler;
{$asmMode intel}
asm
  mov r12, ctid
  mov r13, lock
  mov r14, top
  mov r15, raw
  jmp obte_spin
obte_raw:                 { call r15: the assembler takes label targets only }
  push r15
  ret
obte_spin:
  mov eax, 1
  xchg [r13], eax
  test eax, eax
  jz obte_got
  pause
  jmp obte_spin
obte_got:
  mov rsp, r14
  xor eax, eax
  mov [r12], eax
  sub rsp, 80
  mov qword [rsp], 83
  mov [rsp+8], r12
  mov qword [rsp+16], 2
  mov qword [rsp+24], $7FFFFFFF
  mov qword [rsp+32], 0
  mov qword [rsp+40], 0
  mov qword [rsp+48], 0
  mov rdi, rsp
  call obte_raw
  mov qword [rsp], 83
  mov [rsp+8], r12
  mov qword [rsp+16], 130
  mov qword [rsp+24], $7FFFFFFF
  mov qword [rsp+32], 0
  mov qword [rsp+40], 0
  mov qword [rsp+48], 0
  mov rdi, rsp
  call obte_raw
  mov qword [rsp], 302
  mov [rsp+8], r13
  mov rdi, rsp
  call obte_raw
end;
{$endif}

var
  ObRdx: Int64;

{$ifdef PXX_OBSD_LIBC}
{ The raw call's contract (result, or -OpenBSD errno) over libc's (-1 and
  errno). errno is cleared first: a few calls (getpriority) may answer -1. }
function ObSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var r, m, o: Int64; e: PInteger;
begin
  ObRdx := 0;
  e := PInteger(Lc_errno);
  e^ := 0;
  case nr of
    OB_SIGPROCMASK: begin                             { kernel: mask by value, old mask returned }
                      m := a1; o := 0;
                      r := Int64(LongInt(Lc_sigprocmask(a0, Int64(@m), Int64(@o), 0, 0, 0)));
                      if r = 0 then r := o and $FFFFFFFF;
                    end;
    OB_SIGPENDING:  begin
                      o := 0;
                      r := Int64(LongInt(Lc_sigpending(Int64(@o), 0, 0, 0, 0, 0)));
                      if r = 0 then r := o and $FFFFFFFF;
                    end;
    OB_SIGSUSPEND:  begin
                      m := a0;
                      r := Int64(LongInt(Lc_sigsuspend(Int64(@m), 0, 0, 0, 0, 0)));
                    end;
    OB_GETCWD:      begin                             { libc answers the buffer, or NULL }
                      r := Lc_getcwd(a0, a1, 0, 0, 0, 0);
                      if r = 0 then r := -1 else r := 0;
                    end;
    OB_EXIT: r := Int64(LongInt(Lc_exit(a0, a1, a2, a3, a4, a5)));
    OB_FORK: r := Int64(LongInt(Lc_fork(a0, a1, a2, a3, a4, a5)));
    OB_READ: r := Lc_read(a0, a1, a2, a3, a4, a5);
    OB_WRITE: r := Lc_write(a0, a1, a2, a3, a4, a5);
    OB_CLOSE: r := Int64(LongInt(Lc_close(a0, a1, a2, a3, a4, a5)));
    OB_GETENTROPY: r := Int64(LongInt(Lc_getentropy(a0, a1, a2, a3, a4, a5)));
    OB_LINK: r := Int64(LongInt(Lc_link(a0, a1, a2, a3, a4, a5)));
    OB_UNLINK: r := Int64(LongInt(Lc_unlink(a0, a1, a2, a3, a4, a5)));
    OB_WAIT4: r := Int64(LongInt(Lc_wait4(a0, a1, a2, a3, a4, a5)));
    OB_CHDIR: r := Int64(LongInt(Lc_chdir(a0, a1, a2, a3, a4, a5)));
    OB_FCHDIR: r := Int64(LongInt(Lc_fchdir(a0, a1, a2, a3, a4, a5)));
    OB_MKNOD: r := Int64(LongInt(Lc_mknod(a0, a1, a2, a3, a4, a5)));
    OB_CHMOD: r := Int64(LongInt(Lc_chmod(a0, a1, a2, a3, a4, a5)));
    OB_CHOWN: r := Int64(LongInt(Lc_chown(a0, a1, a2, a3, a4, a5)));
    OB_GETRUSAGE: r := Int64(LongInt(Lc_getrusage(a0, a1, a2, a3, a4, a5)));
    OB_GETPID: r := Int64(LongInt(Lc_getpid(a0, a1, a2, a3, a4, a5)));
    OB_SETUID: r := Int64(LongInt(Lc_setuid(a0, a1, a2, a3, a4, a5)));
    OB_GETUID: r := Int64(LongInt(Lc_getuid(a0, a1, a2, a3, a4, a5)));
    OB_GETEUID: r := Int64(LongInt(Lc_geteuid(a0, a1, a2, a3, a4, a5)));
    OB_RECVMSG: r := Lc_recvmsg(a0, a1, a2, a3, a4, a5);
    OB_SENDMSG: r := Lc_sendmsg(a0, a1, a2, a3, a4, a5);
    OB_RECVFROM: r := Lc_recvfrom(a0, a1, a2, a3, a4, a5);
    OB_ACCEPT: r := Int64(LongInt(Lc_accept(a0, a1, a2, a3, a4, a5)));
    OB_GETPEERNAME: r := Int64(LongInt(Lc_getpeername(a0, a1, a2, a3, a4, a5)));
    OB_GETSOCKNAME: r := Int64(LongInt(Lc_getsockname(a0, a1, a2, a3, a4, a5)));
    OB_SYNC: r := Int64(LongInt(Lc_sync(a0, a1, a2, a3, a4, a5)));
    OB_GETPPID: r := Int64(LongInt(Lc_getppid(a0, a1, a2, a3, a4, a5)));
    OB_DUP: r := Int64(LongInt(Lc_dup(a0, a1, a2, a3, a4, a5)));
    OB_FSTATAT: r := Int64(LongInt(Lc_fstatat(a0, a1, a2, a3, a4, a5)));
    OB_GETEGID: r := Int64(LongInt(Lc_getegid(a0, a1, a2, a3, a4, a5)));
    OB_SIGACTION: r := Int64(LongInt(Lc_sigaction(a0, a1, a2, a3, a4, a5)));
    OB_GETGID: r := Int64(LongInt(Lc_getgid(a0, a1, a2, a3, a4, a5)));
    OB_MMAP: r := Lc_mmap(a0, a1, a2, a3, a4, a5);
    OB_FSTAT: r := Int64(LongInt(Lc_fstat(a0, a1, a2, a3, a4, a5)));
    OB_IOCTL: r := Int64(LongInt(Lc_ioctl(a0, a1, a2, a3, a4, a5)));
    OB_SYMLINK: r := Int64(LongInt(Lc_symlink(a0, a1, a2, a3, a4, a5)));
    OB_READLINK: r := Lc_readlink(a0, a1, a2, a3, a4, a5);
    OB_EXECVE: r := Int64(LongInt(Lc_execve(a0, a1, a2, a3, a4, a5)));
    OB_UMASK: r := Int64(LongInt(Lc_umask(a0, a1, a2, a3, a4, a5)));
    OB_STATFS: r := Int64(LongInt(Lc_statfs(a0, a1, a2, a3, a4, a5)));
    OB_FSTATFS: r := Int64(LongInt(Lc_fstatfs(a0, a1, a2, a3, a4, a5)));
    OB_GETTIMEOFDAY: r := Int64(LongInt(Lc_gettimeofday(a0, a1, a2, a3, a4, a5)));
    OB_SETITIMER: r := Int64(LongInt(Lc_setitimer(a0, a1, a2, a3, a4, a5)));
    OB_GETITIMER: r := Int64(LongInt(Lc_getitimer(a0, a1, a2, a3, a4, a5)));
    OB_SELECT: r := Int64(LongInt(Lc_select(a0, a1, a2, a3, a4, a5)));
    OB_KEVENT: r := Int64(LongInt(Lc_kevent(a0, a1, a2, a3, a4, a5)));
    OB_MUNMAP: r := Int64(LongInt(Lc_munmap(a0, a1, a2, a3, a4, a5)));
    OB_MPROTECT: r := Int64(LongInt(Lc_mprotect(a0, a1, a2, a3, a4, a5)));
    OB_MADVISE: r := Int64(LongInt(Lc_madvise(a0, a1, a2, a3, a4, a5)));
    OB_UTIMES: r := Int64(LongInt(Lc_utimes(a0, a1, a2, a3, a4, a5)));
    OB_GETGROUPS: r := Int64(LongInt(Lc_getgroups(a0, a1, a2, a3, a4, a5)));
    OB_SETGROUPS: r := Int64(LongInt(Lc_setgroups(a0, a1, a2, a3, a4, a5)));
    OB_GETPGRP: r := Int64(LongInt(Lc_getpgrp(a0, a1, a2, a3, a4, a5)));
    OB_SETPGID: r := Int64(LongInt(Lc_setpgid(a0, a1, a2, a3, a4, a5)));
    OB_FUTEX: r := Int64(LongInt(Lc_futex(a0, a1, a2, a3, a4, a5)));
    OB_UTIMENSAT: r := Int64(LongInt(Lc_utimensat(a0, a1, a2, a3, a4, a5)));
    OB_FUTIMENS: r := Int64(LongInt(Lc_futimens(a0, a1, a2, a3, a4, a5)));
    OB_CLOCK_GETTIME: r := Int64(LongInt(Lc_clock_gettime(a0, a1, a2, a3, a4, a5)));
    OB_CLOCK_SETTIME: r := Int64(LongInt(Lc_clock_settime(a0, a1, a2, a3, a4, a5)));
    OB_CLOCK_GETRES: r := Int64(LongInt(Lc_clock_getres(a0, a1, a2, a3, a4, a5)));
    OB_DUP2: r := Int64(LongInt(Lc_dup2(a0, a1, a2, a3, a4, a5)));
    OB_NANOSLEEP: r := Int64(LongInt(Lc_nanosleep(a0, a1, a2, a3, a4, a5)));
    OB_FCNTL: r := Int64(LongInt(Lc_fcntl(a0, a1, a2, a3, a4, a5)));
    OB_ACCEPT4: r := Int64(LongInt(Lc_accept4(a0, a1, a2, a3, a4, a5)));
    OB_FSYNC: r := Int64(LongInt(Lc_fsync(a0, a1, a2, a3, a4, a5)));
    OB_SETPRIORITY: r := Int64(LongInt(Lc_setpriority(a0, a1, a2, a3, a4, a5)));
    OB_SOCKET: r := Int64(LongInt(Lc_socket(a0, a1, a2, a3, a4, a5)));
    OB_CONNECT: r := Int64(LongInt(Lc_connect(a0, a1, a2, a3, a4, a5)));
    OB_GETDENTS: r := Int64(LongInt(Lc_getdents(a0, a1, a2, a3, a4, a5)));
    OB_GETPRIORITY: r := Int64(LongInt(Lc_getpriority(a0, a1, a2, a3, a4, a5)));
    OB_PIPE2: r := Int64(LongInt(Lc_pipe2(a0, a1, a2, a3, a4, a5)));
    OB_DUP3: r := Int64(LongInt(Lc_dup3(a0, a1, a2, a3, a4, a5)));
    OB_BIND: r := Int64(LongInt(Lc_bind(a0, a1, a2, a3, a4, a5)));
    OB_SETSOCKOPT: r := Int64(LongInt(Lc_setsockopt(a0, a1, a2, a3, a4, a5)));
    OB_LISTEN: r := Int64(LongInt(Lc_listen(a0, a1, a2, a3, a4, a5)));
    OB_PPOLL: r := Int64(LongInt(Lc_ppoll(a0, a1, a2, a3, a4, a5)));
    OB_PSELECT: r := Int64(LongInt(Lc_pselect(a0, a1, a2, a3, a4, a5)));
    OB_GETSOCKOPT: r := Int64(LongInt(Lc_getsockopt(a0, a1, a2, a3, a4, a5)));
    OB_THRKILL: r := Int64(LongInt(Lc_thrkill(a0, a1, a2, a3, a4, a5)));
    OB_READV: r := Lc_readv(a0, a1, a2, a3, a4, a5);
    OB_WRITEV: r := Lc_writev(a0, a1, a2, a3, a4, a5);
    OB_KILL: r := Int64(LongInt(Lc_kill(a0, a1, a2, a3, a4, a5)));
    OB_FCHOWN: r := Int64(LongInt(Lc_fchown(a0, a1, a2, a3, a4, a5)));
    OB_FCHMOD: r := Int64(LongInt(Lc_fchmod(a0, a1, a2, a3, a4, a5)));
    OB_SETREUID: r := Int64(LongInt(Lc_setreuid(a0, a1, a2, a3, a4, a5)));
    OB_SETREGID: r := Int64(LongInt(Lc_setregid(a0, a1, a2, a3, a4, a5)));
    OB_RENAME: r := Int64(LongInt(Lc_rename(a0, a1, a2, a3, a4, a5)));
    OB_FLOCK: r := Int64(LongInt(Lc_flock(a0, a1, a2, a3, a4, a5)));
    OB_SENDTO: r := Lc_sendto(a0, a1, a2, a3, a4, a5);
    OB_SHUTDOWN: r := Int64(LongInt(Lc_shutdown(a0, a1, a2, a3, a4, a5)));
    OB_SOCKETPAIR: r := Int64(LongInt(Lc_socketpair(a0, a1, a2, a3, a4, a5)));
    OB_MKDIR: r := Int64(LongInt(Lc_mkdir(a0, a1, a2, a3, a4, a5)));
    OB_RMDIR: r := Int64(LongInt(Lc_rmdir(a0, a1, a2, a3, a4, a5)));
    OB_GETTHRNAME: r := Int64(LongInt(Lc_getthrname(a0, a1, a2, a3, a4, a5)));
    OB_SETTHRNAME: r := Int64(LongInt(Lc_setthrname(a0, a1, a2, a3, a4, a5)));
    OB_SETSID: r := Int64(LongInt(Lc_setsid(a0, a1, a2, a3, a4, a5)));
    OB_LSEEK: r := Lc_lseek(a0, a1, a2, a3, a4, a5);
    OB_TRUNCATE: r := Int64(LongInt(Lc_truncate(a0, a1, a2, a3, a4, a5)));
    OB_FTRUNCATE: r := Int64(LongInt(Lc_ftruncate(a0, a1, a2, a3, a4, a5)));
    OB_PREAD: r := Lc_pread(a0, a1, a2, a3, a4, a5);
    OB_PWRITE: r := Lc_pwrite(a0, a1, a2, a3, a4, a5);
    OB_PREADV: r := Lc_preadv(a0, a1, a2, a3, a4, a5);
    OB_PWRITEV: r := Lc_pwritev(a0, a1, a2, a3, a4, a5);
    OB_SETGID: r := Int64(LongInt(Lc_setgid(a0, a1, a2, a3, a4, a5)));
    OB_GETRLIMIT: r := Int64(LongInt(Lc_getrlimit(a0, a1, a2, a3, a4, a5)));
    OB_SETRLIMIT: r := Int64(LongInt(Lc_setrlimit(a0, a1, a2, a3, a4, a5)));
    OB_SYSCTL: r := Int64(LongInt(Lc_sysctl(a0, a1, a2, a3, a4, a5)));
    OB_MLOCK: r := Int64(LongInt(Lc_mlock(a0, a1, a2, a3, a4, a5)));
    OB_MUNLOCK: r := Int64(LongInt(Lc_munlock(a0, a1, a2, a3, a4, a5)));
    OB_GETPGID: r := Int64(LongInt(Lc_getpgid(a0, a1, a2, a3, a4, a5)));
    OB_POLL: r := Int64(LongInt(Lc_poll(a0, a1, a2, a3, a4, a5)));
    OB_LCHOWN: r := Int64(LongInt(Lc_lchown(a0, a1, a2, a3, a4, a5)));
    OB_GETSID: r := Int64(LongInt(Lc_getsid(a0, a1, a2, a3, a4, a5)));
    OB_KQUEUE: r := Int64(LongInt(Lc_kqueue(a0, a1, a2, a3, a4, a5)));
    OB_MLOCKALL: r := Int64(LongInt(Lc_mlockall(a0, a1, a2, a3, a4, a5)));
    OB_MUNLOCKALL: r := Int64(LongInt(Lc_munlockall(a0, a1, a2, a3, a4, a5)));
    OB_GETRESUID: r := Int64(LongInt(Lc_getresuid(a0, a1, a2, a3, a4, a5)));
    OB_SETRESUID: r := Int64(LongInt(Lc_setresuid(a0, a1, a2, a3, a4, a5)));
    OB_GETRESGID: r := Int64(LongInt(Lc_getresgid(a0, a1, a2, a3, a4, a5)));
    OB_SETRESGID: r := Int64(LongInt(Lc_setresgid(a0, a1, a2, a3, a4, a5)));
    OB_SIGALTSTACK: r := Int64(LongInt(Lc_sigaltstack(a0, a1, a2, a3, a4, a5)));
    OB_SCHED_YIELD: r := Int64(LongInt(Lc_sched_yield(a0, a1, a2, a3, a4, a5)));
    OB_GETTHRID: r := Int64(LongInt(Lc_getthrid(a0, a1, a2, a3, a4, a5)));
    OB_THREXIT: r := Int64(LongInt(Lc_threxit(a0, a1, a2, a3, a4, a5)));
    OB_THRSIGDIVERT: r := Int64(LongInt(Lc_thrsigdivert(a0, a1, a2, a3, a4, a5)));
    OB_FACCESSAT: r := Int64(LongInt(Lc_faccessat(a0, a1, a2, a3, a4, a5)));
    OB_FCHMODAT: r := Int64(LongInt(Lc_fchmodat(a0, a1, a2, a3, a4, a5)));
    OB_FCHOWNAT: r := Int64(LongInt(Lc_fchownat(a0, a1, a2, a3, a4, a5)));
    OB_LINKAT: r := Int64(LongInt(Lc_linkat(a0, a1, a2, a3, a4, a5)));
    OB_MKDIRAT: r := Int64(LongInt(Lc_mkdirat(a0, a1, a2, a3, a4, a5)));
    OB_MKNODAT: r := Int64(LongInt(Lc_mknodat(a0, a1, a2, a3, a4, a5)));
    OB_OPENAT: r := Int64(LongInt(Lc_openat(a0, a1, a2, a3, a4, a5)));
    OB_READLINKAT: r := Lc_readlinkat(a0, a1, a2, a3, a4, a5);
    OB_RENAMEAT: r := Int64(LongInt(Lc_renameat(a0, a1, a2, a3, a4, a5)));
    OB_SYMLINKAT: r := Int64(LongInt(Lc_symlinkat(a0, a1, a2, a3, a4, a5)));
    OB_UNLINKAT: r := Int64(LongInt(Lc_unlinkat(a0, a1, a2, a3, a4, a5)));
    OB_SET_TCB: r := Int64(LongInt(Lc_set_tcb(a0, a1, a2, a3, a4, a5)));
    OB_GET_TCB: r := Lc_get_tcb(a0, a1, a2, a3, a4, a5);
  else
    r := -1; e^ := 78;                                { ENOSYS }
  end;
  if (r = -1) and (e^ <> 0) then r := -e^;
  Result := r;
end;
{$else}
function ObSys(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
var a: array[0..8] of Int64;
begin
  a[0] := nr; a[1] := a0; a[2] := a1; a[3] := a2;
  a[4] := a3; a[5] := a4; a[6] := a5; a[7] := 0; a[8] := 0;
  Result := ObRawA(@a[0]);
  ObRdx := a[7];
end;
{$endif}

{ -OpenBSD errno -> -Linux errno; anything else unchanged. }
function Lx(r: Int64): Int64;
begin
  if (r < -34) and (r >= -95) then Result := -ErrMap[Integer(-r)]
  else Result := r;
end;

function ObOpenFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and 3;                                       { O_ACCMODE, same }
  if (f and $40) <> 0 then r := r or $200;            { O_CREAT }
  if (f and $80) <> 0 then r := r or $800;            { O_EXCL }
  if (f and $100) <> 0 then r := r or $8000;          { O_NOCTTY }
  if (f and $200) <> 0 then r := r or $400;           { O_TRUNC }
  if (f and $400) <> 0 then r := r or $8;             { O_APPEND }
  if (f and $800) <> 0 then r := r or $4;             { O_NONBLOCK }
  if (f and $1000) <> 0 then r := r or $80;           { O_DSYNC / O_SYNC }
  if (f and $10000) <> 0 then r := r or $20000;       { O_DIRECTORY }
  if (f and $20000) <> 0 then r := r or $100;         { O_NOFOLLOW }
  if (f and $80000) <> 0 then r := r or $10000;       { O_CLOEXEC }
  Result := r;                                        { O_LARGEFILE, O_NOATIME, O_DIRECT, O_PATH: dropped }
end;

function LxOpenFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and 3;
  if (f and $200) <> 0 then r := r or $40;
  if (f and $800) <> 0 then r := r or $80;
  if (f and $8000) <> 0 then r := r or $100;
  if (f and $400) <> 0 then r := r or $200;
  if (f and $8) <> 0 then r := r or $400;
  if (f and $4) <> 0 then r := r or $800;
  if (f and $80) <> 0 then r := r or $101000;
  if (f and $20000) <> 0 then r := r or $10000;
  if (f and $100) <> 0 then r := r or $20000;
  if (f and $10000) <> 0 then r := r or $80000;
  Result := r;
end;

{ Linux MAP_* -> OpenBSD. NOT a pass-through: Linux MAP_NORESERVE ($4000)
  is OpenBSD's MAP_STACK and Linux MAP_POPULATE ($8000) is MAP_CONCEAL. }
function ObMmapFlags(f: Int64): Int64;
var r: Int64;
begin
  r := f and $13;                                     { SHARED, PRIVATE, FIXED: same }
  if (f and $20) <> 0 then r := r or OB_MAP_ANON;
  if (f and $20000) <> 0 then r := r or OB_MAP_STACK;
  Result := r;
end;

function ObAtFlags(f: Int64): Int64;
var r: Int64;
begin
  r := 0;
  if (f and $100) <> 0 then r := r or OB_AT_SYMLINK_NOFOLLOW;
  if (f and $400) <> 0 then r := r or OB_AT_SYMLINK_FOLLOW;
  Result := r;
end;

{ Linux clocks: REALTIME 0, MONOTONIC 1, PROCESS_CPUTIME 2, THREAD_CPUTIME 3,
  MONOTONIC_RAW 4, REALTIME_COARSE 5, MONOTONIC_COARSE 6, BOOTTIME 7.
  OpenBSD: REALTIME 0, PROCESS_CPUTIME 2, MONOTONIC 3, THREAD_CPUTIME 4,
  UPTIME 5, BOOTTIME 6. }
function ObClock(id: Int64): Int64;
begin
  case Integer(id) of
    0: Result := 0;
    1: Result := 3;
    2: Result := 2;
    3: Result := 4;
    4: Result := 3;
    5: Result := 0;
    6: Result := 3;
    7: Result := 6;
  else
    Result := id;
  end;
end;

function ObSig(s: Int64): Int64;
begin
  if (s >= 0) and (s <= 31) then Result := SigMap[Integer(s)]
  else Result := s;
end;

{ OpenBSD struct stat (128 B) at ob -> Linux x86-64 struct stat (144 B). }
procedure StatToLinux(ob, lx: Pointer);
var i: Integer;
begin
  for i := 0 to 17 do PInt64(Int64(lx) + i * 8)^ := 0;
  PInt64(Int64(lx) + 0)^ := PLongWord(Int64(ob) + 4)^;              { st_dev }
  PInt64(Int64(lx) + 8)^ := PInt64(Int64(ob) + 8)^;                 { st_ino }
  PInt64(Int64(lx) + 16)^ := PLongWord(Int64(ob) + 16)^;            { st_nlink }
  PLongWord(Int64(lx) + 24)^ := PLongWord(Int64(ob) + 0)^;          { st_mode }
  PLongWord(Int64(lx) + 28)^ := PLongWord(Int64(ob) + 20)^;         { st_uid }
  PLongWord(Int64(lx) + 32)^ := PLongWord(Int64(ob) + 24)^;         { st_gid }
  PInt64(Int64(lx) + 40)^ := PLongWord(Int64(ob) + 28)^;            { st_rdev }
  PInt64(Int64(lx) + 48)^ := PInt64(Int64(ob) + 80)^;               { st_size }
  PInt64(Int64(lx) + 56)^ := PInteger(Int64(ob) + 96)^;             { st_blksize }
  PInt64(Int64(lx) + 64)^ := PInt64(Int64(ob) + 88)^;               { st_blocks }
  PInt64(Int64(lx) + 72)^ := PInt64(Int64(ob) + 32)^;               { st_atim }
  PInt64(Int64(lx) + 80)^ := PInt64(Int64(ob) + 40)^;
  PInt64(Int64(lx) + 88)^ := PInt64(Int64(ob) + 48)^;               { st_mtim }
  PInt64(Int64(lx) + 96)^ := PInt64(Int64(ob) + 56)^;
  PInt64(Int64(lx) + 104)^ := PInt64(Int64(ob) + 64)^;              { st_ctim }
  PInt64(Int64(lx) + 112)^ := PInt64(Int64(ob) + 72)^;
end;

{ OpenBSD struct stat -> Linux struct statx (256 B). }
procedure StatToStatx(ob, sx: Pointer);
var i: Integer;
procedure Ts(lxOff, obOff: Integer);
begin
  PInt64(Int64(sx) + lxOff)^ := PInt64(Int64(ob) + obOff)^;
  PLongWord(Int64(sx) + lxOff + 8)^ := LongWord(PInt64(Int64(ob) + obOff + 8)^);
end;
begin
  for i := 0 to 31 do PInt64(Int64(sx) + i * 8)^ := 0;
  PLongWord(Int64(sx) + 0)^ := $FFF;                                { BASIC_STATS | BTIME }
  PLongWord(Int64(sx) + 4)^ := LongWord(PInteger(Int64(ob) + 96)^); { blksize }
  PLongWord(Int64(sx) + 16)^ := PLongWord(Int64(ob) + 16)^;         { nlink }
  PLongWord(Int64(sx) + 20)^ := PLongWord(Int64(ob) + 20)^;         { uid }
  PLongWord(Int64(sx) + 24)^ := PLongWord(Int64(ob) + 24)^;         { gid }
  PWord(Int64(sx) + 28)^ := PWord(Int64(ob) + 0)^;                  { mode }
  PInt64(Int64(sx) + 32)^ := PInt64(Int64(ob) + 8)^;                { ino }
  PInt64(Int64(sx) + 40)^ := PInt64(Int64(ob) + 80)^;               { size }
  PInt64(Int64(sx) + 48)^ := PInt64(Int64(ob) + 88)^;               { blocks }
  Ts(64, 32);                                                       { atime }
  Ts(80, 112);                                                      { btime }
  Ts(96, 64);                                                       { ctime }
  Ts(112, 48);                                                      { mtime }
  PLongWord(Int64(sx) + 128)^ := (PLongWord(Int64(ob) + 28)^ shr 8) and $FF;  { rdev major }
  PLongWord(Int64(sx) + 132)^ := PLongWord(Int64(ob) + 28)^ and $FF;          { rdev minor }
  PLongWord(Int64(sx) + 136)^ := (PLongWord(Int64(ob) + 4)^ shr 8) and $FF;   { dev major }
  PLongWord(Int64(sx) + 140)^ := PLongWord(Int64(ob) + 4)^ and $FF;           { dev minor }
end;

{ OpenBSD dirents -> Linux dirent64, in place. The name moves from offset 24
  to 19 -- over d_namlen, so the length is read first. Each record keeps its
  d_reclen, which is still large enough. }
procedure DirentsToLinux(buf: Pointer; n: Int64);
var p, recLen, nameLen, i: Int64;
begin
  p := 0;
  while p < n do
  begin
    recLen := PWord(Int64(buf) + p + 16)^;
    nameLen := PByte(Int64(buf) + p + 19)^;
    if recLen = 0 then Exit;
    for i := 0 to nameLen do        { includes the NUL }
      PByte(Int64(buf) + p + 19 + i)^ := PByte(Int64(buf) + p + 24 + i)^;
    p := p + recLen;
  end;
end;

{ Linux brk on a PROT_NONE reservation grown with mprotect. OpenBSD has no
  brk syscall at all. Linux semantics: the new break on success, the old one
  on failure, never an error code. }
function ObBrk(want: Int64): Int64;
var top, r: Int64;
begin
  if ObBrkBase = 0 then
  begin
    r := ObSys(OB_MMAP, 0, BRK_RESERVE, 0, 2 or OB_MAP_ANON, -1, 0);   { PROT_NONE, PRIVATE|ANON }
    if r < 0 then begin Result := 0; Exit; end;
    ObBrkBase := r; ObBrkCur := r; ObBrkTop := r;
  end;
  Result := ObBrkCur;
  if (want < ObBrkBase) or (want > ObBrkBase + BRK_RESERVE) then Exit;
  if want > ObBrkTop then
  begin
    top := (want + $FFFF) and (not Int64($FFFF));
    if top > ObBrkBase + BRK_RESERVE then top := ObBrkBase + BRK_RESERVE;
    r := ObSys(OB_MPROTECT, ObBrkTop, top - ObBrkTop, 3, 0, 0, 0);
    if r < 0 then Exit;
    ObBrkTop := top;
  end;
  ObBrkCur := want;
  Result := want;
end;

function StrLen0(p: Int64): Int64;
var n: Int64;
begin
  n := 0;
  while PByte(p + n)^ <> 0 do n := n + 1;
  Result := n;
end;

procedure SysctlStr(m0, m1: Integer; dst: Int64; cap: Int64);
var mib: array[0..1] of Integer; len: Int64;
begin
  mib[0] := m0; mib[1] := m1; len := cap - 1;
  if ObSys(OB_SYSCTL, Int64(@mib[0]), 2, dst, Int64(@len), 0, 0) < 0 then len := 0;
  if len > cap - 1 then len := cap - 1;
  PByte(dst + len)^ := 0;
end;

{ Linux struct utsname: six 65-byte fields, built from sysctl as libc does. }
function ObUname(u: Int64): Int64;
var i: Integer;
const
  SysName: array[0..6] of Byte = (79, 112, 101, 110, 66, 83, 68);   { OpenBSD }
  Machine: array[0..5] of Byte = (120, 56, 54, 95, 54, 52);         { x86_64 }
begin
  for i := 0 to 389 do PByte(u + i)^ := 0;
  for i := 0 to 6 do PByte(u + i)^ := SysName[i];
  SysctlStr(1, 10, u + 65, 65);      { kern.hostname }
  SysctlStr(1, 2, u + 130, 65);      { kern.osrelease }
  SysctlStr(1, 4, u + 195, 65);      { kern.version }
  for i := 0 to 5 do PByte(u + 260 + i)^ := Machine[i];
  Result := 0;
end;

function ObGetRlimit(res, lim: Int64): Int64;
var r: Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  if RlimMap[Integer(res)] < 0 then
  begin
    PInt64(lim)^ := -1; PInt64(lim + 8)^ := -1;      { RLIMIT_AS: unlimited }
    Result := 0; Exit;
  end;
  r := ObSys(OB_GETRLIMIT, RlimMap[Integer(res)], lim, 0, 0, 0, 0);
  if r = 0 then
  begin
    if PInt64(lim)^ = OB_RLIM_INFINITY then PInt64(lim)^ := -1;
    if PInt64(lim + 8)^ = OB_RLIM_INFINITY then PInt64(lim + 8)^ := -1;
  end;
  Result := Lx(r);
end;

function ObSetRlimit(res, lim: Int64): Int64;
var v: array[0..1] of Int64;
begin
  if (res < 0) or (res > 9) then begin Result := -LX_EINVAL; Exit; end;
  if RlimMap[Integer(res)] < 0 then begin Result := 0; Exit; end;
  v[0] := PInt64(lim)^; v[1] := PInt64(lim + 8)^;
  if v[0] = -1 then v[0] := OB_RLIM_INFINITY;
  if v[1] = -1 then v[1] := OB_RLIM_INFINITY;
  Result := Lx(ObSys(OB_SETRLIMIT, RlimMap[Integer(res)], Int64(@v[0]), 0, 0, 0, 0));
end;

{ fstatat with Linux flags; AT_EMPTY_PATH ($1000) with "" is fstat(dirfd). }
function ObStatAt(dirfd, path, buf, flags: Int64): Int64;
var sb: array[0..15] of Int64; r: Int64;
begin
  if ((flags and $1000) <> 0) and ((path = 0) or (PByte(path)^ = 0)) then
    r := ObSys(OB_FSTAT, dirfd, Int64(@sb[0]), 0, 0, 0, 0)
  else
    r := ObSys(OB_FSTATAT, dirfd, path, Int64(@sb[0]), ObAtFlags(flags), 0, 0);
  if r = 0 then StatToLinux(@sb[0], Pointer(buf));
  Result := Lx(r);
end;

{ ---- /proc files the runtime reads ------------------------------------- }

function PathIs(p: Int64; w: PByte; n: Integer): Boolean;   { pointer + count: see MapBits }
var i: Integer;
begin
  Result := False;
  if p = 0 then Exit;
  for i := 0 to n - 1 do
    if PByte(p + i)^ <> w[i] then Exit;
  Result := PByte(p + n)^ = 0;
end;

const
  ProcEnviron: array[0..17] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                       101,110,118,105,114,111,110);   { /proc/self/environ }
  ProcExe: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,
                                   101,120,101);                        { /proc/self/exe }
  ProcHostname: array[0..24] of Byte = (47,112,114,111,99,47,115,121,115,47,107,101,
                                        114,110,101,108,47,104,111,115,116,110,97,
                                        109,101);                       { /proc/sys/kernel/hostname }
  DevFull: array[0..8] of Byte = (47,100,101,118,47,102,117,108,108);  { /dev/full }
  DevZero: array[0..9] of Byte = (47,100,101,118,47,122,101,114,111,0); { /dev/zero, NUL-terminated }

{ An fd that reads back len bytes from buf. OpenBSD has no anonymous shm and
  no memfd, so: a pipe when the bytes fit its buffer (16 KiB, no file system
  touched), else an unlinked file in /tmp. }
function ObDataFd(buf, len: Int64): Int64;
var fds: array[0..1] of Integer; name: array[0..47] of Byte;
    fd, v, i, k: Int64;
const Pre: array[0..10] of Byte = (47,116,109,112,47,46,112,120,120,101,110);   { /tmp/.pxxen }
begin
  if len <= 16384 then
  begin
    fds[0] := -1; fds[1] := -1;
    Result := ObSys(OB_PIPE2, Int64(@fds[0]), $10000, 0, 0, 0, 0);    { O_CLOEXEC }
    if Result < 0 then begin Result := Lx(Result); Exit; end;
    if len > 0 then ObSys(OB_WRITE, fds[1], buf, len, 0, 0, 0);
    ObSys(OB_CLOSE, fds[1], 0, 0, 0, 0, 0);
    Result := fds[0];
    Exit;
  end;
  for i := 0 to 10 do name[i] := Pre[i];
  k := 11;
  ObTmpSeq := ObTmpSeq + 1;
  v := ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0) * 1000 + ObTmpSeq;
  while v > 0 do begin name[k] := 48 + (v mod 10); v := v div 10; k := k + 1; end;
  name[k] := 0;
  fd := ObSys(OB_OPENAT, OB_AT_FDCWD, Int64(@name[0]), 2 or $200 or $800 or $10000, 384, 0, 0);
  if fd < 0 then begin Result := Lx(fd); Exit; end;
  ObSys(OB_UNLINK, Int64(@name[0]), 0, 0, 0, 0, 0);
  ObSys(OB_WRITE, fd, buf, len, 0, 0, 0);
  ObSys(OB_LSEEK, fd, 0, 0, 0, 0, 0);
  Result := fd;
end;

{ kern.proc.args.<pid>.{argv,env}: a NULL-terminated pointer array (pointers
  into the same buffer) followed by the strings. Returns the mapping (size in
  sz) or a negative errno. }
function ObProcArgs(what: Integer; var sz: Int64): Int64;
var mib: array[0..3] of Integer; len, buf, r: Int64;
begin
  mib[0] := 1; mib[1] := 55;
  mib[2] := Integer(ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0)); mib[3] := what;
  sz := 256 * 1024;
  buf := ObSys(OB_MMAP, 0, sz, 3, 2 or OB_MAP_ANON, -1, 0);
  if buf < 0 then begin Result := -LX_ENOMEM; Exit; end;
  len := sz;
  r := ObSys(OB_SYSCTL, Int64(@mib[0]), 4, buf, Int64(@len), 0, 0);
  if r < 0 then
  begin
    ObSys(OB_MUNMAP, buf, sz, 0, 0, 0, 0);
    Result := Lx(r); Exit;
  end;
  Result := buf;
end;

{ /proc/self/environ: "k=v\0k=v\0", from kern.proc.args.env. }
function ObProcEnviron: Int64;
var buf, sz, outp, n, p, s, i: Int64;
begin
  buf := ObProcArgs(3, sz);
  if buf < 0 then begin Result := buf; Exit; end;
  outp := ObSys(OB_MMAP, 0, sz, 3, 2 or OB_MAP_ANON, -1, 0);
  if outp < 0 then begin ObSys(OB_MUNMAP, buf, sz, 0, 0, 0, 0); Result := -LX_ENOMEM; Exit; end;
  n := 0; p := buf;
  while PInt64(p)^ <> 0 do
  begin
    s := PInt64(p)^;
    i := 0;
    while (PByte(s + i)^ <> 0) and (n < sz - 1) do
    begin
      PByte(outp + n)^ := PByte(s + i)^; n := n + 1; i := i + 1;
    end;
    PByte(outp + n)^ := 0; n := n + 1;
    p := p + 8;
  end;
  Result := ObDataFd(outp, n);
  ObSys(OB_MUNMAP, outp, sz, 0, 0, 0, 0);
  ObSys(OB_MUNMAP, buf, sz, 0, 0, 0, 0);
end;

{ /proc/sys/kernel/hostname: kern.hostname and a newline. }
function ObProcHostname: Int64;
var b: array[0..271] of Byte; n: Int64;
begin
  SysctlStr(1, 10, Int64(@b[0]), 256);
  n := StrLen0(Int64(@b[0]));
  b[n] := 10;
  Result := ObDataFd(Int64(@b[0]), n + 1);
end;

{ readlink("/proc/self/exe"). OpenBSD keeps no path for a running image, so
  this is argv[0] made absolute with the cwd -- right whenever the program
  was started by a path (./x, /usr/bin/x), -ENOENT when it came from a PATH
  search. Linux semantics: no NUL, truncated, byte count returned. }
function ObProcExe(buf, cap: Int64): Int64;
var a, sz, s, n, m, i: Int64; tmp: array[0..1023] of Byte; hasSlash: Boolean;
begin
  a := ObProcArgs(1, sz);
  if a < 0 then begin Result := a; Exit; end;
  s := PInt64(a)^;
  hasSlash := False;
  if s <> 0 then
  begin
    i := 0;
    while PByte(s + i)^ <> 0 do begin if PByte(s + i)^ = 47 then hasSlash := True; i := i + 1; end;
  end;
  if (s = 0) or not hasSlash then
  begin
    ObSys(OB_MUNMAP, a, sz, 0, 0, 0, 0);
    Result := -LX_ENOENT; Exit;
  end;
  n := 0;
  if PByte(s)^ <> 47 then
  begin
    if ObSys(OB_GETCWD, Int64(@tmp[0]), 900, 0, 0, 0, 0) >= 0 then
    begin
      n := StrLen0(Int64(@tmp[0]));
      if (n > 0) and (tmp[n - 1] <> 47) then begin tmp[n] := 47; n := n + 1; end;
    end;
    if (PByte(s)^ = 46) and (PByte(s + 1)^ = 47) then s := s + 2;   { "./x" -> "x" }
  end;
  m := StrLen0(s);
  i := 0;
  while (i < m) and (n < 1023) do begin tmp[n] := PByte(s + i)^; n := n + 1; i := i + 1; end;
  ObSys(OB_MUNMAP, a, sz, 0, 0, 0, 0);
  if n > cap then n := cap;
  for i := 0 to n - 1 do PByte(buf + i)^ := tmp[i];
  Result := n;
end;

{ ---- Signals ----------------------------------------------------------------
  fbsdabi's design (read its Signals header): the program's handler speaks
  the Linux SA_SIGINFO ABI and may REWRITE the saved RIP/RSP in the Linux
  ucontext it is given (the fault-to-raise path), so rt_sigaction installs
  ObSigEntry instead. ObSigEntry builds a Linux siginfo/ucontext, calls the
  program's handler, copies the registers back into OpenBSD's struct
  sigcontext (the handler's third argument on amd64; ucontext_t IS
  sigcontext there), and returns to the kernel's sigcode, which does
  sigreturn. The sigcontext's sc_cookie is never touched.

  What differs from FreeBSD:
  - sigset_t is ONE 32-bit word, and sigprocmask/sigpending/sigsuspend pass
    it by value in a register (the old mask comes back in rax).
  - siginfo is signo, CODE, errno (Linux: signo, errno, code). si_code values
    agree with Linux for faults (FPE_INTDIV 1, FPE_INTOVF 2 -- no FreeBSD
    swap); the user codes are 0, -1 (LWP), -2 (QUEUE), -3 (TIMER).
  - OpenBSD kills a process that makes a syscall with rsp outside a
    MAP_STACK mapping. pxx's alt stack is 32 KiB of BSS, but sigaltstack
    converts what it registers (see ObSigaltstack), so it passes through.
  Offsets measured with offsetof() on OpenBSD 8.0 (2026-11-12). }

const
  OB_SA_ONSTACK = $1; OB_SA_RESTART = $2; OB_SA_RESETHAND = $4;
  OB_SA_NOCLDSTOP = $8; OB_SA_NODEFER = $10; OB_SA_NOCLDWAIT = $20;
  OB_SA_SIGINFO = $40;
  LX_SA_NOCLDSTOP = $1; LX_SA_NOCLDWAIT = $2; LX_SA_SIGINFO = $4;
  LX_SA_ONSTACK = $08000000; LX_SA_RESTART = $10000000;
  LX_SA_NODEFER = $40000000; LX_SA_RESETHAND = $80000000;
  { Linux gregs[0..17] (R8 R9 R10 R11 R12 R13 R14 R15 RDI RSI RBP RBX RDX RAX
    RCX RSP RIP EFL) -> offset in OpenBSD struct sigcontext. }
  ObGregOff: array[0..17] of Integer = (
    32, 40, 48, 56, 64, 72, 80, 88, 0, 8, 96, 104, 16, 112, 24, 192, 168, 184);
  OB_SC_TRAPNO = 152; OB_SC_ERR = 160; OB_SC_FPSTATE = 208; OB_SC_MASK = 220;
  LX_UC_GREGS = 40;
  LX_UC_SIGMASK = 296;
  LX_UC_SIGMASK_A64 = 40;

var
  ObLxHandler: array[0..32] of Int64;   { by OpenBSD signal number }

function LxSig(s: Int64): Int64;
var i: Integer;
begin
  for i := 1 to 31 do
    if SigMap[i] = s then begin Result := i; Exit; end;
  Result := s;
end;

{ Linux 64-bit mask -> OpenBSD 32-bit mask. Signals with no OpenBSD
  equivalent (16, 30, the real-time range) drop out. }
function MaskToOb(lx: Int64): Int64;
var s, b: Int64;
begin
  Result := 0;
  for s := 1 to 31 do
    if ((lx shr (s - 1)) and 1) <> 0 then
    begin
      b := SigMap[Integer(s)];
      if (b >= 1) and (b <= 32) then Result := Result or (Int64(1) shl (b - 1));
    end;
end;

function MaskToLx(ob: Int64): Int64;
var b, s: Int64;
begin
  Result := 0;
  for b := 1 to 32 do
    if ((ob shr (b - 1)) and 1) <> 0 then
    begin
      s := LxSig(b);
      if (s >= 1) and (s <= 64) then Result := Result or (Int64(1) shl (s - 1));
    end;
end;

function SaFlagsToOb(f: Int64): Int64;
begin
  Result := 0;
  if (f and LX_SA_NOCLDSTOP) <> 0 then Result := Result or OB_SA_NOCLDSTOP;
  if (f and LX_SA_NOCLDWAIT) <> 0 then Result := Result or OB_SA_NOCLDWAIT;
  if (f and LX_SA_SIGINFO) <> 0 then Result := Result or OB_SA_SIGINFO;
  if (f and LX_SA_ONSTACK) <> 0 then Result := Result or OB_SA_ONSTACK;
  if (f and LX_SA_RESTART) <> 0 then Result := Result or OB_SA_RESTART;
  if (f and LX_SA_NODEFER) <> 0 then Result := Result or OB_SA_NODEFER;
  if (f and LX_SA_RESETHAND) <> 0 then Result := Result or OB_SA_RESETHAND;
end;

function SaFlagsToLx(f: Int64): Int64;
begin
  Result := 0;
  if (f and OB_SA_NOCLDSTOP) <> 0 then Result := Result or LX_SA_NOCLDSTOP;
  if (f and OB_SA_NOCLDWAIT) <> 0 then Result := Result or LX_SA_NOCLDWAIT;
  if (f and OB_SA_SIGINFO) <> 0 then Result := Result or LX_SA_SIGINFO;
  if (f and OB_SA_ONSTACK) <> 0 then Result := Result or LX_SA_ONSTACK;
  if (f and OB_SA_RESTART) <> 0 then Result := Result or LX_SA_RESTART;
  if (f and OB_SA_NODEFER) <> 0 then Result := Result or LX_SA_NODEFER;
  if (f and OB_SA_RESETHAND) <> 0 then Result := Result or LX_SA_RESETHAND;
end;

{ OpenBSD si_code -> Linux si_code. Fault codes (> 0) agree. }
function LxSiCode(c: Int64): Int64;
begin
  case c of
    -1: Result := -6;          { SI_LWP -> SI_TKILL }
    -2: Result := -1;          { SI_QUEUE }
    -3: Result := -2;          { SI_TIMER }
  else
    Result := c;
  end;
end;

{ OpenBSD siginfo_t (ob) -> Linux siginfo_t (lx, 128 bytes). }
procedure SiginfoToLx(ob, lx: Int64);
var i: Integer; c: Int64;
begin
  for i := 0 to 15 do PInt64(lx + i * 8)^ := 0;
  PInteger(lx)^ := Integer(LxSig(PInteger(ob)^));             { si_signo }
  PInteger(lx + 4)^ := PInteger(ob + 8)^;                     { si_errno }
  c := PInteger(ob + 4)^;
  PInteger(lx + 8)^ := Integer(LxSiCode(c));                  { si_code }
  if c <= 0 then
  begin
    PInteger(lx + 16)^ := PInteger(ob + 16)^;                 { si_pid }
    PInteger(lx + 20)^ := PInteger(ob + 20)^;                 { si_uid }
  end
  else
    PInt64(lx + 16)^ := PInt64(ob + 16)^;                     { si_addr }
end;

type
  TObLxHandler = procedure(sig, info, uc: Int64); cdecl;

{$ifdef CPU_AARCH64}
const
  { OpenBSD/arm64 struct sigcontext (sys/arch/arm64/include/signal.h): mask
    at 4, sp 8, lr 16, elr 24, spsr 32, x0..x29 at 40, cookie 280; no FP
    registers. Linux arm64's mcontext is at 176 in its ucontext:
    fault_address, x0..x30, sp, pc, pstate. }
  OB_A64_SC_MASK = 4; OB_A64_SC_SP = 8; OB_A64_SC_LR = 16;
  OB_A64_SC_ELR = 24; OB_A64_SC_SPSR = 32; OB_A64_SC_X = 40;
  LX_A64_MC = 176;

{ The handler OpenBSD calls (x0 sig, x1 siginfo, x2 sigcontext); it returns
  to the kernel's sigcode, which does sigreturn. }
procedure ObSigEntry(sig, info, sc: Int64); cdecl;
var li: array[0..15] of Int64;
    lu: array[0..63] of Int64;
    i, m: Integer;
    h, ls: Int64;
begin
  if (sig < 1) or (sig > 32) then Exit;
  h := ObLxHandler[Integer(sig)];
  if h = 0 then Exit;
  ls := LxSig(sig);
  for i := 0 to 63 do lu[i] := 0;
  if info <> 0 then SiginfoToLx(info, Int64(@li[0]))
  else
  begin
    for i := 0 to 15 do li[i] := 0;
    PInteger(@li[0])^ := Integer(ls);
  end;
  m := LX_A64_MC div 8;
  if sc <> 0 then
  begin
    for i := 0 to 29 do lu[m + 1 + i] := PInt64(sc + OB_A64_SC_X + 8 * i)^;
    lu[m + 31] := PInt64(sc + OB_A64_SC_LR)^;
    lu[m + 32] := PInt64(sc + OB_A64_SC_SP)^;
    lu[m + 33] := PInt64(sc + OB_A64_SC_ELR)^;
    lu[m + 34] := PInt64(sc + OB_A64_SC_SPSR)^;
    if (info <> 0) and (PInteger(info + 4)^ > 0) then lu[m] := PInt64(info + 16)^;
    lu[LX_UC_SIGMASK_A64 div 8] := MaskToLx(PLongWord(sc + OB_A64_SC_MASK)^);
  end;
  if info <> 0 then TObLxHandler(h)(ls, Int64(@li[0]), Int64(@lu[0]))
  else TObLxHandler(h)(ls, 0, Int64(@lu[0]));
  if sc <> 0 then
  begin
    for i := 0 to 29 do PInt64(sc + OB_A64_SC_X + 8 * i)^ := lu[m + 1 + i];
    PInt64(sc + OB_A64_SC_LR)^ := lu[m + 31];
    PInt64(sc + OB_A64_SC_SP)^ := lu[m + 32];
    PInt64(sc + OB_A64_SC_ELR)^ := lu[m + 33];
  end;
end;
{$else}
{ The handler OpenBSD actually calls (SA_SIGINFO: rdi, rsi, rdx = sigcontext). }
procedure ObSigEntry(sig, info, sc: Int64); cdecl;
var li: array[0..15] of Int64;        { Linux siginfo_t, 128 B }
    lu: array[0..63] of Int64;        { Linux ucontext_t through uc_sigmask }
    i: Integer;
    h, ls: Int64;
begin
  if (sig < 1) or (sig > 32) then Exit;
  h := ObLxHandler[Integer(sig)];
  if h = 0 then Exit;
  ls := LxSig(sig);
  for i := 0 to 63 do lu[i] := 0;
  if info <> 0 then SiginfoToLx(info, Int64(@li[0]))
  else
  begin
    for i := 0 to 15 do li[i] := 0;
    PInteger(@li[0])^ := Integer(ls);
  end;
  if sc <> 0 then
  begin
    for i := 0 to 17 do
      lu[LX_UC_GREGS div 8 + i] := PInt64(sc + ObGregOff[i])^;
    lu[LX_UC_GREGS div 8 + 19] := PInt64(sc + OB_SC_ERR)^;              { ERR }
    lu[LX_UC_GREGS div 8 + 20] := PInt64(sc + OB_SC_TRAPNO)^;           { TRAPNO }
    if (info <> 0) and (PInteger(info + 4)^ > 0) then
      lu[LX_UC_GREGS div 8 + 22] := PInt64(info + 16)^;                 { CR2 = fault address }
    lu[LX_UC_SIGMASK div 8] := MaskToLx(PLongWord(sc + OB_SC_MASK)^);
    { An SSE floating-point trap: OpenBSD 8.0 reports FPE_FLTINV whatever the
      cause, and leaves sc_trapno 0 (both measured with
      test_float_exception_mask). Linux names the cause from the saved MXCSR,
      the flags that are set AND unmasked, in this priority order -- and
      FPC-style runtime errors depend on it. So a FLTINV with a saved FPU
      state is re-derived the Linux way; no set-and-unmasked flag leaves it. }
    if (sig = 8) and (info <> 0) and (PInteger(info + 4)^ = 7)
       and (PInt64(sc + OB_SC_FPSTATE)^ <> 0) then
    begin
      h := PLongWord(PInt64(sc + OB_SC_FPSTATE)^ + 24)^;          { fx_mxcsr }
      h := h and (not (h shr 7)) and $3F;
      if (h and $01) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 7          { FPE_FLTINV }
      else if (h and $04) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 3     { FPE_FLTDIV }
      else if (h and $08) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 4     { FPE_FLTOVF }
      else if (h and $12) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 5     { FPE_FLTUND }
      else if (h and $20) <> 0 then PInteger(Int64(@li[0]) + 8)^ := 6;    { FPE_FLTRES }
      h := ObLxHandler[Integer(sig)];
    end;
  end;
  if info <> 0 then TObLxHandler(h)(ls, Int64(@li[0]), Int64(@lu[0]))
  else TObLxHandler(h)(ls, 0, Int64(@lu[0]));
  if sc <> 0 then
    for i := 0 to 17 do
      PInt64(sc + ObGregOff[i])^ := lu[LX_UC_GREGS div 8 + i];
end;
{$endif}

function ObRtSigaction(sig, act, oact: Int64): Int64;
var oa, oo: array[0..1] of Int64;     { OpenBSD struct sigaction, 16 B }
    os, h, oldh, r: Int64;
begin
  os := ObSig(sig);
  if (os < 1) or (os > 32) then begin Result := -LX_EINVAL; Exit; end;
  oldh := ObLxHandler[Integer(os)];
  oa[0] := 0; oa[1] := 0; oo[0] := 0; oo[1] := 0;
  if act <> 0 then
  begin
    h := PInt64(act)^;
    PLongWord(Int64(@oa[0]) + 8)^ := LongWord(MaskToOb(PInt64(act + 24)^));
    PInteger(Int64(@oa[0]) + 12)^ := Integer(SaFlagsToOb(PInt64(act + 8)^));
    if (h = 0) or (h = 1) then oa[0] := h                 { SIG_DFL / SIG_IGN }
    else
    begin
      ObLxHandler[Integer(os)] := h;
      oa[0] := Int64(@ObSigEntry);
      PInteger(Int64(@oa[0]) + 12)^ := PInteger(Int64(@oa[0]) + 12)^ or OB_SA_SIGINFO;
    end;
    r := ObSys(OB_SIGACTION, os, Int64(@oa[0]), Int64(@oo[0]), 0, 0, 0);
    if r <> 0 then ObLxHandler[Integer(os)] := oldh
    else if (h = 0) or (h = 1) then ObLxHandler[Integer(os)] := 0;
  end
  else
    r := ObSys(OB_SIGACTION, os, 0, Int64(@oo[0]), 0, 0, 0);
  if (r = 0) and (oact <> 0) then
  begin
    if oo[0] = Int64(@ObSigEntry) then PInt64(oact)^ := oldh
    else PInt64(oact)^ := oo[0];
    PInt64(oact + 8)^ := SaFlagsToLx(PInteger(Int64(@oo[0]) + 12)^);
    PInt64(oact + 16)^ := 0;
    PInt64(oact + 24)^ := MaskToLx(PLongWord(Int64(@oo[0]) + 8)^);
  end;
  Result := Lx(r);
end;

{ The current mask, without changing it: SIG_BLOCK with an empty set. }
function ObCurMask: Int64;
begin
  Result := ObSys(OB_SIGPROCMASK, 1, 0, 0, 0, 0, 0) and $FFFFFFFF;
end;

function ObRtSigprocmask(how, nset, oset: Int64): Int64;
var r: Int64;
begin
  if (how < 0) or (how > 2) then begin Result := -LX_EINVAL; Exit; end;
  if nset <> 0 then r := ObSys(OB_SIGPROCMASK, how + 1, MaskToOb(PInt64(nset)^), 0, 0, 0, 0)
  else r := ObSys(OB_SIGPROCMASK, 1, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if oset <> 0 then PInt64(oset)^ := MaskToLx(r and $FFFFFFFF);
  Result := 0;
end;

{ sigaltstack: Linux stack_t is sp, flags(int), size; OpenBSD's is sp, size,
  flags; SS_DISABLE is 2 on Linux and 4 on OpenBSD. The program's buffer is
  registered as it is, BSS or not: OpenBSD converts a registered alt stack to
  MAP_STACK itself (measured 2026-11-12: a handler on pxx's BSS alt stack
  makes syscalls and lives, where any other non-MAP_STACK rsp is killed). }
function ObSigaltstack(ss, oss: Int64): Int64;
var t, o: array[0..2] of Int64; r, f, pt, po: Int64;
begin
  pt := 0; po := 0;
  if ss <> 0 then
  begin
    t[0] := PInt64(ss)^;
    t[1] := PInt64(ss + 16)^;
    f := PInteger(ss + 8)^;
    t[2] := 0;
    if (f and 1) <> 0 then t[2] := t[2] or 1;          { SS_ONSTACK }
    if (f and 2) <> 0 then t[2] := t[2] or 4;          { SS_DISABLE }
    pt := Int64(@t[0]);
  end;
  if oss <> 0 then po := Int64(@o[0]);
  r := ObSys(OB_SIGALTSTACK, pt, po, 0, 0, 0, 0);
  if (r = 0) and (oss <> 0) then
  begin
    PInt64(oss)^ := o[0];
    f := 0;
    if (PInteger(@o[2])^ and 1) <> 0 then f := f or 1;
    if (PInteger(@o[2])^ and 4) <> 0 then f := f or 2;
    PInteger(oss + 8)^ := Integer(f);
    PInt64(oss + 16)^ := o[1];
  end;
  Result := Lx(r);
end;

function ObThrKill(tid, sig: Int64): Int64;
var os: Int64;
begin
  os := ObSig(sig);
  if (os = 0) and (sig <> 0) then begin Result := -LX_EINVAL; Exit; end;
  if tid = ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0) then tid := 0;   { 0 = this thread }
  Result := Lx(ObSys(OB_THRKILL, tid, os, 0, 0, 0, 0));
end;

{ ---- Threads -----------------------------------------------------------------
  The clone stub's OpenBSD leg (thread_emit.inc) calls clone through the
  thunk, with the child's resume address in r9. Linux flags are honoured as
  far as pxx uses them: the stack, PARENT_SETTID (tf_tid), CHILD_CLEARTID
  (the ctid pointer is parked in the child's TLS block, which the stub has
  already carved at stage+16, and acted on by the thread's exit), and the
  TLS block itself (tf_tcb = the same block, so fs is right from the first
  instruction). }

{$ifdef PXX_OBSD_LIBC}
{ arch_prctl(SET_GS, block) under libc: the thread's block cannot move (it
  is where ld.so put it, below fs), so the given one is copied in, and its
  self-pointer (slot 0) names the real place. }
function ObSetBlock(blk: Int64): Int64;
var dst, i: Int64;
begin
  dst := ObMyBlock;
  if blk <> dst then
    for i := 0 to __pxxTlsBlockSize div 8 - 1 do
      PInt64(dst + 8 * i)^ := PInt64(blk + 8 * i)^;
  PInt64(dst)^ := dst;
  Result := 0;
end;
{$endif}

function ObClone(flags, stack, ptid, ctid, cont: Int64): Int64;
var p: array[0..2] of Int64;
begin
  if ((flags and $100) = 0) or (stack = 0) or (cont = 0) then
  begin
    Result := -LX_EINVAL; Exit;                           { only CLONE_VM threads }
  end;
  if ObMainTid = 0 then ObMainTid := ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0);
  if ObExitStack = 0 then
  begin
    Result := ObSys(OB_MMAP, 0, OB_EXIT_STACK_SIZE, 3, 2 or OB_MAP_ANON or OB_MAP_STACK, -1, 0);
    if Result < 0 then begin Result := -LX_ENOMEM; Exit; end;
    ObExitStack := Result;
  end;
  if (flags and $00200000) <> 0 then                      { CLONE_CHILD_CLEARTID }
    PInt64(stack + 16 + 8 * OB_TLS_SLOT_CTID)^ := ctid
  else
    PInt64(stack + 16 + 8 * OB_TLS_SLOT_CTID)^ := 0;
{$ifdef PXX_OBSD_LIBC}
  { libc owns fs: the child's fs is a thread block from ld.so, with the pxx
    block below it (PT_TLS). Its init-image slot starts as the parent's, as
    the stub's read through gs expects; the child's arch_prctl copies the
    staged block in (ObSetBlock). Not freed when the thread ends (the thread
    cannot free its own; a leak of one block per thread). }
  p[0] := Lc_dl_allocate_tib(0);
  if p[0] = 0 then begin Result := -LX_ENOMEM; Exit; end;
  PInt64(p[0] - ObTlsSpan + 8 * 13)^ := PInt64(ObMyBlock + 8 * 13)^;   { TLS_SLOT_INIT_IMAGE }
{$else}
  p[0] := stack + 16;                                     { tf_tcb = the TLS block }
{$endif}
  if (flags and $00100000) <> 0 then p[1] := ptid         { CLONE_PARENT_SETTID }
  else p[1] := 0;
  p[2] := stack;                                          { tf_stack }
  Result := Lx(ObTforkA(Int64(@p[0]), 24, cont));
end;

{ exit(2): this thread. The main thread (or a program that never made one)
  ends the process, as pxx's runtime expects. }
procedure ObExitThread(code: Int64);
var ctid: Int64;
begin
  if (ObMainTid = 0) or (ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0) = ObMainTid) then
    ObSys(OB_EXIT, code, 0, 0, 0, 0, 0);
  ctid := PInt64(Int64(__pxxTlsBase) + 8 * OB_TLS_SLOT_CTID)^;
  if ctid = 0 then ObSys(OB_THREXIT, 0, 0, 0, 0, 0, 0);
  { The kernel stores the tid through tf_tid; wait until it has, or the
    clear below would be undone and the joiner would wait for a dead thread. }
  while PInteger(ctid)^ = 0 do ObSys(OB_SCHED_YIELD, 0, 0, 0, 0, 0, 0);
  ObThreadExitA(ctid, Int64(@ObExitLock), ObExitStack + OB_EXIT_STACK_SIZE, Int64(@ObRawA));
end;

{ futex: Linux WAIT 0, WAKE 1, REQUEUE 3, WAIT_BITSET 9, WAKE_BITSET 10;
  OpenBSD WAIT 1, WAKE 2, REQUEUE 3; FUTEX_PRIVATE_FLAG is 128 on both.
  A bitset op with a full mask is the plain op. Timeouts are relative on
  both for WAIT (a BITSET wait's absolute timeout is refused). }
function ObFutex(uaddr, op, val, ts, uaddr2, val3: Int64): Int64;
var o, pf: Int64;
begin
  pf := op and 128;
  case op and 127 of
    0: o := 1;
    1: o := 2;
    3: o := 3;
    9: begin
         if (val3 and $FFFFFFFF) <> $FFFFFFFF then begin Result := -LX_EINVAL; Exit; end;
         if ts <> 0 then begin Result := -LX_EINVAL; Exit; end;
         o := 1;
       end;
    10: begin
          if (val3 and $FFFFFFFF) <> $FFFFFFFF then begin Result := -LX_EINVAL; Exit; end;
          o := 2;
        end;
  else
    Result := -LX_ENOSYS; Exit;
  end;
  if o = 3 then
    Result := Lx(ObSys(OB_FUTEX, uaddr, o or pf, val, ts, uaddr2, 0))   { ts = the requeue count }
  else
    Result := Lx(ObSys(OB_FUTEX, uaddr, o or pf, val, ts, 0, 0));
end;

{ ---- Sockets -----------------------------------------------------------------
  fbsdabi's code with OpenBSD's numbers: the structs are FreeBSD's (BSD
  sockaddr header -- u8 length, u8 family; 48-byte msghdr with 32-bit
  iovlen/controllen; 12-byte cmsghdr with the data at 16; 104-byte sun_path).
  What differs from FreeBSD: AF_INET6 is 24, SOCK_NONBLOCK/SOCK_CLOEXEC are
  $4000/$8000, MSG_NOSIGNAL is $400 and MSG_CMSG_CLOEXEC $800, accept4 is 93,
  there is no SO_DOMAIN/SO_PROTOCOL or TCP_KEEP*, and SO_PEERCRED ($1022) is
  uid, gid, pid where Linux's ucred is pid, uid, gid. Measured on 8.0 with
  offsetof() and the headers (2026-11-12). }
const
  OB_SOCKET = 97; OB_CONNECT = 98; OB_ACCEPT = 30; OB_SENDTO = 133;
  OB_RECVFROM = 29; OB_SENDMSG = 28; OB_RECVMSG = 27; OB_SHUTDOWN = 134;
  OB_BIND = 104; OB_LISTEN = 106; OB_GETSOCKNAME = 32; OB_GETPEERNAME = 31;
  OB_SOCKETPAIR = 135; OB_SETSOCKOPT = 105; OB_GETSOCKOPT = 118; OB_ACCEPT4 = 93;
  LX_EAFNOSUPPORT = 97; LX_ENOPROTOOPT = 92;

function ObAf(a: Int64): Int64;
begin
  case a of
    0, 1, 2: Result := a;
    10: Result := 24;
  else Result := -1;
  end;
end;

function LxAf(a: Int64): Int64;
begin
  if a = 24 then Result := 10 else Result := a;
end;

{ SOCK_NONBLOCK / SOCK_CLOEXEC ride in the type word on both, at other bits. }
function ObSockType(t: Int64): Int64;
begin
  Result := t and $FF;
  if (t and $800) <> 0 then Result := Result or $4000;
  if (t and $80000) <> 0 then Result := Result or $8000;
end;

function ObMsgFlags(f: Int64): Int64;
begin
  Result := f and $7;                                          { OOB PEEK DONTROUTE }
  if (f and $8) <> 0 then Result := Result or $20;             { CTRUNC }
  if (f and $20) <> 0 then Result := Result or $10;            { TRUNC }
  if (f and $40) <> 0 then Result := Result or $80;            { DONTWAIT }
  if (f and $80) <> 0 then Result := Result or $8;             { EOR }
  if (f and $100) <> 0 then Result := Result or $40;           { WAITALL }
  if (f and $4000) <> 0 then Result := Result or $400;         { NOSIGNAL }
  if (f and $40000000) <> 0 then Result := Result or $800;     { CMSG_CLOEXEC }
end;

function LxMsgFlags(f: Int64): Int64;
begin
  Result := f and $7;
  if (f and $20) <> 0 then Result := Result or $8;
  if (f and $10) <> 0 then Result := Result or $20;
  if (f and $80) <> 0 then Result := Result or $40;
  if (f and $8) <> 0 then Result := Result or $80;
  if (f and $40) <> 0 then Result := Result or $100;
end;

{ Linux sockaddr (src, len) -> BSD sockaddr in dst (128 B). Answers the
  length to pass, or -errno. }
function SaToOb(src, len, dst: Int64): Int64;
var i, af: Int64;
begin
  if (src = 0) or (len < 2) then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  for i := 0 to len - 1 do PByte(dst + i)^ := PByte(src + i)^;
  af := ObAf(PWord(src)^);
  if af < 0 then begin Result := -LX_EAFNOSUPPORT; Exit; end;
  if (af = 1) and (len > 106) then len := 106;                  { sun_path 108 -> 104 }
  PByte(dst)^ := Byte(len);
  PByte(dst + 1)^ := Byte(af);
  Result := len;
end;

{ BSD sockaddr at p, in place, -> Linux shape. }
procedure SaToLx(p, lenp: Int64);
begin
  if (p = 0) or (lenp = 0) or (PInteger(lenp)^ < 2) then Exit;
  PWord(p)^ := Word(LxAf(PByte(p + 1)^));
end;

{ socket option (level, name) -> OpenBSD; level -1 = no equivalent. }
procedure SockOptToOb(var level, name: Int64);
begin
  case level of
    1: begin                                                    { SOL_SOCKET }
         level := $FFFF;
         case name of
           1: name := $1; 2: name := $4; 3: name := $1008; 4: name := $1007;
           5: name := $10; 6: name := $20; 7: name := $1001; 8: name := $1002;
           9: name := $8; 10: name := $100; 13: name := $80; 15: name := $200;
           18: name := $1004; 19: name := $1003; 20: name := $1006; 21: name := $1005;
           30: name := $2; 17: name := $1022;                     { SO_PEERCRED }
         else level := -1;
         end;
       end;
    6: case name of                                             { IPPROTO_TCP }
         1, 2: ;
       else level := -1;
       end;
    0: case name of                                             { IPPROTO_IP }
         1: name := 3; 2: name := 4;
         32: name := 9; 33: name := 10; 34: name := 11; 35: name := 12; 36: name := 13;
       else level := -1;
       end;
    41: case name of                                            { IPPROTO_IPV6 }
          26: name := 27; 16: name := 4; 17: name := 9; 18: name := 10;
          19: name := 11; 20: name := 12; 21: name := 13;
        else level := -1;
        end;
  else
    if level <> 17 then level := -1;                            { IPPROTO_UDP: nothing renumbered }
  end;
end;

function ObSockopt(isGet: Boolean; fd, level, name, val, lenp: Int64): Int64;
var lv, nm, r, e: Int64;
begin
  lv := level; nm := name;
  SockOptToOb(lv, nm);
  if lv < 0 then begin Result := -LX_ENOPROTOOPT; Exit; end;
  if not isGet then
  begin
    Result := Lx(ObSys(OB_SETSOCKOPT, fd, lv, nm, val, lenp, 0));
    Exit;
  end;
  r := ObSys(OB_GETSOCKOPT, fd, lv, nm, val, lenp, 0);
  if (r = 0) and (lv = $FFFF) and (val <> 0) then
  begin
    if nm = $1007 then                                          { SO_ERROR holds an errno }
    begin
      e := PInteger(val)^;
      if (e >= 35) and (e <= 95) then PInteger(val)^ := ErrMap[Integer(e)];
    end
    else if (nm = $1022) and (lenp <> 0) and (PInteger(lenp)^ >= 12) then
    begin                                                       { sockpeercred -> ucred }
      e := PInteger(val + 8)^;                                  { pid }
      PInteger(val + 8)^ := PInteger(val + 4)^;                 { gid }
      PInteger(val + 4)^ := PInteger(val)^;                     { uid }
      PInteger(val)^ := Integer(e);
    end;
  end;
  Result := Lx(r);
end;

function ObSockAddrCall(nr, fd, sa, len: Int64): Int64;    { connect, bind }
var b: array[0..15] of Int64; n: Int64;
begin
  n := SaToOb(sa, len, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(ObSys(nr, fd, Int64(@b[0]), n, 0, 0, 0));
end;

function ObSockAddrOut(nr, fd, sa, lenp, flags: Int64): Int64;  { accept4, getsockname, getpeername }
var r: Int64;
begin
  if nr = OB_ACCEPT4 then
  begin
    r := 0;
    if (flags and $800) <> 0 then r := r or $4000;
    if (flags and $80000) <> 0 then r := r or $8000;
    r := ObSys(nr, fd, sa, lenp, r, 0, 0);
  end
  else r := ObSys(nr, fd, sa, lenp, 0, 0, 0);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

function ObSendto(fd, buf, len, flags, sa, salen: Int64): Int64;
var b: array[0..15] of Int64; n: Int64;
begin
  if sa = 0 then
  begin
    Result := Lx(ObSys(OB_SENDTO, fd, buf, len, ObMsgFlags(flags), 0, 0));
    Exit;
  end;
  n := SaToOb(sa, salen, Int64(@b[0]));
  if n < 0 then Result := n
  else Result := Lx(ObSys(OB_SENDTO, fd, buf, len, ObMsgFlags(flags), Int64(@b[0]), n));
end;

function ObRecvfrom(fd, buf, len, flags, sa, lenp: Int64): Int64;
var r: Int64;
begin
  r := ObSys(OB_RECVFROM, fd, buf, len, ObMsgFlags(flags), sa, lenp);
  if r >= 0 then SaToLx(sa, lenp);
  Result := Lx(r);
end;

{ Linux cmsg chain (size_t len, int level, int type; data at 16) <-> OpenBSD
  (u32 len, int level, int type; data at 16 -- _ALIGN(12) on amd64). Rewritten
  in place: both headers fit the same 16 bytes and the data does not move.
  SOL_SOCKET is the only level renumbered; SCM_RIGHTS is 1 on both. }
procedure CmsgToOb(ctl, clen: Int64);
var p, l: Int64;
begin
  p := ctl;
  while (ctl <> 0) and (p + 16 <= ctl + clen) do
  begin
    l := PInt64(p)^;
    if l < 16 then Exit;
    PInteger(p)^ := Integer(l);
    PInteger(p + 4)^ := PInteger(p + 8)^;                       { level }
    if PInteger(p + 4)^ = 1 then PInteger(p + 4)^ := $FFFF;
    PInteger(p + 8)^ := PInteger(p + 12)^;                      { type }
    PInteger(p + 12)^ := 0;
    p := p + ((l + 7) and not Int64(7));
  end;
end;

procedure CmsgToLx(ctl, clen: Int64);
var p, l, lv, ty: Int64;
begin
  p := ctl;
  while (ctl <> 0) and (p + 16 <= ctl + clen) do
  begin
    l := PInteger(p)^ and $FFFFFFFF;
    if l < 12 then Exit;
    lv := PInteger(p + 4)^; ty := PInteger(p + 8)^;
    if lv = $FFFF then lv := 1;
    PInt64(p)^ := l;                                            { CMSG_LEN(n) = 16 + n on both }
    PInteger(p + 8)^ := Integer(lv);
    PInteger(p + 12)^ := Integer(ty);
    p := p + ((l + 7) and not Int64(7));
  end;
end;

{ msghdr: Linux 56 B (size_t iovlen/controllen, flags at 48), OpenBSD 48 B. }
function ObMsg(isSend: Boolean; fd, lm, flags: Int64): Int64;
var fm: array[0..5] of Int64;
    nb: array[0..15] of Int64;
    r, n: Int64;
begin
  fm[0] := PInt64(lm)^;                                         { msg_name }
  fm[1] := PInteger(lm + 8)^;                                   { msg_namelen (int, upper 4 = 0) }
  fm[2] := PInt64(lm + 16)^;                                    { msg_iov }
  fm[3] := PInt64(lm + 24)^ and $FFFFFFFF;                      { msg_iovlen }
  fm[4] := PInt64(lm + 32)^;                                    { msg_control }
  fm[5] := PInt64(lm + 40)^ and $FFFFFFFF;                      { msg_controllen; flags = 0 }
  if isSend then
  begin
    if fm[0] <> 0 then
    begin
      n := SaToOb(fm[0], fm[1], Int64(@nb[0]));
      if n < 0 then begin Result := n; Exit; end;
      fm[0] := Int64(@nb[0]); fm[1] := n;
    end;
    CmsgToOb(fm[4], fm[5]);
    r := ObSys(OB_SENDMSG, fd, Int64(@fm[0]), ObMsgFlags(flags), 0, 0, 0);
    CmsgToLx(fm[4], fm[5]);                                     { the caller's buffer, restored }
  end
  else
  begin
    r := ObSys(OB_RECVMSG, fd, Int64(@fm[0]), ObMsgFlags(flags), 0, 0, 0);
    if r >= 0 then
    begin
      if fm[0] <> 0 then
      begin
        PWord(fm[0])^ := Word(LxAf(PByte(fm[0] + 1)^));
        PInteger(lm + 8)^ := PInteger(Int64(@fm[1]))^;
      end;
      n := PInteger(Int64(@fm[5]))^ and $FFFFFFFF;
      CmsgToLx(fm[4], n);
      PInt64(lm + 40)^ := n;
      PInteger(lm + 48)^ := Integer(LxMsgFlags(PInteger(Int64(@fm[5]) + 4)^));
    end;
  end;
  Result := Lx(r);
end;



const
  OB_KQUEUE = 269; OB_KEVENT = 72;
  OB_EVFILT_READ = -1; OB_EVFILT_WRITE = -2;
  OB_EV_ADD = $1; OB_EV_DELETE = $2; OB_EV_ENABLE = $4; OB_EV_ONESHOT = $10;
  OB_EV_CLEAR = $20; OB_EV_ERROR = $4000; OB_EV_EOF = $8000;
  LX_EPOLLIN = $1; LX_EPOLLPRI = $2; LX_EPOLLOUT = $4; LX_EPOLLERR = $8;
  LX_EPOLLHUP = $10; LX_EPOLLRDHUP = $2000;
  EP_MAX = 64;                    { kevents fetched per epoll_wait }

{ ---- epoll over kqueue ------------------------------------------------------
  fbsdabi's emulation. OpenBSD's struct kevent has FreeBSD's field offsets
  (ident 0, filter 8, flags 10, fflags 12, data 16, udata 24) but no ext[],
  so it is 32 bytes, not 64; the EVFILT_/EV_ values agree (measured on 8.0).
  OpenBSD has no epoll. An epoll instance IS a kqueue; an interest in an fd is
  up to two kevent filters (READ for EPOLLIN/PRI/RDHUP, WRITE for EPOLLOUT)
  carrying the caller's epoll_data as udata. EPOLLET -> EV_CLEAR, EPOLLONESHOT
  -> EV_ONESHOT. epoll_wait folds the READ and WRITE kevents of one fd back
  into one epoll_event, as Linux reports it. struct epoll_event is PACKED on
  x86-64: u32 events at 0, u64 data at 4, 12 bytes. }

function ObKev1(kq, ident, filter, flags, udata: Int64): Int64;
var kv: array[0..3] of Int64;     { struct kevent, 32 B }
    i: Integer;
begin
  for i := 0 to 3 do kv[i] := 0;
  kv[0] := ident;
  PSmallInt(Int64(@kv[0]) + 8)^ := SmallInt(filter);
  PWord(Int64(@kv[0]) + 10)^ := Word(flags);
  kv[3] := udata;
  Result := ObSys(OB_KEVENT, kq, Int64(@kv[0]), 1, 0, 0, 0);
end;

function ObEpollCtl(kq, op, fd, ev: Int64): Int64;
var e, data, fl, r: Int64;
begin
  if (op = 2) or (ev = 0) then                                 { EPOLL_CTL_DEL }
  begin
    r := ObKev1(kq, fd, OB_EVFILT_READ, OB_EV_DELETE, 0);
    if ObKev1(kq, fd, OB_EVFILT_WRITE, OB_EV_DELETE, 0) = 0 then r := 0;
    Result := Lx(r);
    Exit;
  end;
  e := PInteger(ev)^ and $FFFFFFFF;
  data := PInt64(ev + 4)^;
  fl := OB_EV_ADD or OB_EV_ENABLE;
  if (e and $80000000) <> 0 then fl := fl or OB_EV_CLEAR;      { EPOLLET }
  if (e and $40000000) <> 0 then fl := fl or OB_EV_ONESHOT;    { EPOLLONESHOT }
  r := 0;
  if (e and (LX_EPOLLIN or LX_EPOLLPRI or LX_EPOLLRDHUP)) <> 0 then
    r := ObKev1(kq, fd, OB_EVFILT_READ, fl, data)
  else if op = 3 then ObKev1(kq, fd, OB_EVFILT_READ, OB_EV_DELETE, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (e and LX_EPOLLOUT) <> 0 then
    r := ObKev1(kq, fd, OB_EVFILT_WRITE, fl, data)
  else if op = 3 then ObKev1(kq, fd, OB_EVFILT_WRITE, OB_EV_DELETE, 0);
  Result := Lx(r);
end;

function ObEpollWait(kq, evs, maxev, ms: Int64): Int64;
var kv: array[0..EP_MAX * 4 - 1] of Int64;
    ts: array[0..1] of Int64;
    tp, r, i, j, n, e, fl, ident: Int64;
    base: Int64;
begin
  if maxev <= 0 then begin Result := -LX_EINVAL; Exit; end;
  if maxev > EP_MAX then maxev := EP_MAX;
  tp := 0;
  if ms >= 0 then
  begin
    ts[0] := ms div 1000; ts[1] := (ms mod 1000) * 1000000;
    tp := Int64(@ts[0]);
  end;
  r := ObSys(OB_KEVENT, kq, 0, 0, Int64(@kv[0]), maxev, tp);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := 0;
  for i := 0 to r - 1 do
  begin
    base := Int64(@kv[0]) + i * 32;
    ident := PInt64(base)^;
    fl := PWord(base + 10)^;
    e := 0;
    if PSmallInt(base + 8)^ = OB_EVFILT_READ then e := LX_EPOLLIN
    else e := LX_EPOLLOUT;
    if (fl and OB_EV_EOF) <> 0 then
    begin
      e := e or LX_EPOLLHUP;
      if PSmallInt(base + 8)^ = OB_EVFILT_READ then e := e or LX_EPOLLRDHUP;
      if PInteger(base + 12)^ <> 0 then e := e or LX_EPOLLERR;  { fflags = socket error }
    end;
    if (fl and OB_EV_ERROR) <> 0 then e := LX_EPOLLERR;
    { fold into an earlier event for the same fd; kv[] holds ident, the
      output array holds only data -- so match on the kevent list }
    j := 0;
    while j < i do
    begin
      if PInt64(Int64(@kv[0]) + j * 32)^ = ident then Break;
      Inc(j);
    end;
    if j < i then
    begin
      { the earlier kevent j was emitted at output slot PInteger(kv j .data)^ }
      j := PInt64(Int64(@kv[0]) + j * 32 + 16)^;
      PInteger(evs + j * 12)^ := PInteger(evs + j * 12)^ or Integer(e);
      PInt64(base + 16)^ := j;
    end
    else
    begin
      PInteger(evs + n * 12)^ := Integer(e);
      PInt64(evs + n * 12 + 4)^ := PInt64(base + 24)^;
      PInt64(base + 16)^ := n;                                 { remember the slot }
      Inc(n);
    end;
  end;
  Result := n;
end;

{ ---- termios -----------------------------------------------------------------
  Linux's kernel struct termios is 36 bytes (4 flag words, c_line, c_cc[19]),
  with the line speed coded into c_cflag (CBAUD); OpenBSD's is 44 (4 flag
  words, c_cc[20], c_ispeed, c_ospeed as plain numbers). Almost every flag bit
  and every c_cc index differs; a disabled control char is 0 on Linux and
  0xff (_POSIX_VDISABLE) on OpenBSD. fbsdabi's tables, with what OpenBSD 8.0
  measures differently: no IUTF8 (dropped), OCRNL/ONOCR/ONLRET at
  $10/$40/$80, CRTSCTS $10000. The c_cc indices and the ioctl numbers are
  FreeBSD's. }
const
  TIflLx: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$400,$1000,$800,$2000,$4000);
  TIflOb: array[0..13] of Int64 = ($1,$2,$4,$8,$10,$20,$40,$80,$100,$200,$400,$800,$2000,0);   { no IUTF8 }
  TOflLx: array[0..5] of Int64 = ($1,$4,$1800,$8,$10,$20);
  TOflOb: array[0..5] of Int64 = ($1,$2,$4,$10,$40,$80);
  TCflLx: array[0..6] of Int64 = ($40,$80,$100,$200,$400,$800,$80000000);
  TCflOb: array[0..6] of Int64 = ($400,$800,$1000,$2000,$4000,$8000,$10000);
  TLflLx: array[0..13] of Int64 = ($1,$2,$8,$10,$20,$40,$80,$100,$200,$400,$800,$1000,$4000,$8000);
  TLflOb: array[0..13] of Int64 = ($80,$100,$8,$2,$4,$10,$80000000,$400000,$40,$20,$1,$800000,$20000000,$400);
  { Linux c_cc index -> FreeBSD index (-1: VSWTC, none) }
  TCcMap: array[0..16] of Integer = (8,9,3,5,0,17,16,-1,12,13,10,1,6,15,4,14,2);
  { Linux CBAUD codes 0..15 and $1001..$100F as line speeds }
  TBaudLo: array[0..15] of Integer = (0,50,75,110,134,150,200,300,600,1200,1800,2400,4800,9600,19200,38400);
  TBaudHi: array[1..15] of Integer = (57600,115200,230400,460800,500000,576000,921600,
                                      1000000,1152000,1500000,2000000,2500000,3000000,3500000,4000000);

{ pointer + count, not open arrays: on aarch64 a const open-array argument
  is copied with PXXMemMove, which a program that never moves memory does
  not have (fbsdabi's PathIs says the same). }
function MapBits(v: Int64; src, dst: PInt64; n: Integer): Int64;
var i: Integer;
begin
  Result := 0;
  for i := 0 to n - 1 do
    if (src[i] <> 0) and ((v and src[i]) = src[i]) then Result := Result or dst[i];   { 0 = no counterpart }
end;

function SpeedToLx(n: Int64): Int64;
var i: Integer;
begin
  for i := 0 to 15 do if TBaudLo[i] = n then begin Result := i; Exit; end;
  for i := 1 to 15 do if TBaudHi[i] = n then begin Result := $1000 or i; Exit; end;
  Result := 15;                                                 { unknown: B38400 }
end;

function SpeedToOb(c: Int64): Int64;
begin
  c := c and $100F;
  if c <= 15 then Result := TBaudLo[Integer(c)]
  else if (c and $F) >= 1 then Result := TBaudHi[Integer(c and $F)]
  else Result := 38400;
end;

procedure TermiosToLx(fb, lx: Int64);
var i, ix: Integer; c: Byte; cf: Int64;
begin
  for i := 0 to 35 do PByte(lx + i)^ := 0;
  PInteger(lx)^ := Integer(MapBits(PInteger(fb)^, @TIflOb[0], @TIflLx[0], Length(TIflOb)));
  PInteger(lx + 4)^ := Integer(MapBits(PInteger(fb + 4)^, @TOflOb[0], @TOflLx[0], Length(TOflOb)));
  cf := MapBits(PInteger(fb + 8)^ and $FFFFFFFF, @TCflOb[0], @TCflLx[0], Length(TCflOb));
  cf := cf or (((PInteger(fb + 8)^ shr 8) and 3) shl 4);        { CSIZE }
  cf := cf or SpeedToLx(PInteger(fb + 40)^);                    { c_ospeed -> CBAUD }
  PInteger(lx + 8)^ := Integer(cf);
  PInteger(lx + 12)^ := Integer(MapBits(PInteger(fb + 12)^ and $FFFFFFFF, @TLflOb[0], @TLflLx[0], Length(TLflOb)));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(fb + 16 + ix)^;
    if (c = $FF) and (i <> 5) and (i <> 6) then c := 0;         { VTIME/VMIN are numbers }
    PByte(lx + 17 + i)^ := c;
  end;
end;

procedure TermiosToOb(lx, fb: Int64);
var i, ix: Integer; c: Byte; cf, sp: Int64;
begin
  for i := 0 to 43 do PByte(fb + i)^ := 0;
  for i := 0 to 19 do PByte(fb + 16 + i)^ := $FF;
  PInteger(fb)^ := Integer(MapBits(PInteger(lx)^, @TIflLx[0], @TIflOb[0], Length(TIflLx)));
  PInteger(fb + 4)^ := Integer(MapBits(PInteger(lx + 4)^, @TOflLx[0], @TOflOb[0], Length(TOflLx)));
  cf := PInteger(lx + 8)^ and $FFFFFFFF;
  PInteger(fb + 8)^ := Integer(MapBits(cf, @TCflLx[0], @TCflOb[0], Length(TCflLx)) or (((cf shr 4) and 3) shl 8));
  PInteger(fb + 12)^ := Integer(MapBits(PInteger(lx + 12)^, @TLflLx[0], @TLflOb[0], Length(TLflLx)));
  for i := 0 to 16 do
  begin
    ix := TCcMap[i];
    if ix < 0 then Continue;
    c := PByte(lx + 17 + i)^;
    if (c = 0) and (i <> 5) and (i <> 6) then c := $FF;
    PByte(fb + 16 + ix)^ := c;
  end;
  sp := SpeedToOb(cf);
  PInteger(fb + 36)^ := Integer(sp);
  PInteger(fb + 40)^ := Integer(sp);
end;

{ ---- timerfd over kqueue -----------------------------------------------------
  OpenBSD has no timerfd, and pxx's scheduler parks every timed wait on one
  (CoSleep, the *Timeout waits, DNS). A timerfd here is a kqueue holding one
  EVFILT_TIMER: a kqueue fd is itself readable while it has a pending event,
  so epoll (kqueue) and poll see it fire exactly as they would a timerfd. read
  fetches the timer's kevent, whose data is the expiration count -- the u64 a
  timerfd read answers. ObTfd marks which fds are such kqueues (bit 0), their
  TFD_NONBLOCK (bit 1) and CLOCK_REALTIME (bit 2); close clears the mark.
  NOT EMULATED: an interval different from the first expiry (the kqueue timer
  is periodic at one rate: the first fire comes at the interval), and
  timerfd_gettime / the old value (answered as disarmed). }

const
  OB_EVFILT_TIMER = -7;
  OB_NOTE_NSECONDS = 3;
  OB_TFD_MAX = 4096;

var
  ObTfd: array[0..OB_TFD_MAX - 1] of Byte;

function ObIsTfd(fd: Int64): Boolean;
begin
  Result := (fd >= 0) and (fd < OB_TFD_MAX) and ((ObTfd[Integer(fd)] and 1) <> 0);
end;

function ObTimerfdCreate(clock, flags: Int64): Int64;
var r: Int64;
begin
  if (clock <> 0) and (clock <> 1) and (clock <> 7) then begin Result := -LX_EINVAL; Exit; end;
  r := ObSys(OB_KQUEUE, 0, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if r >= OB_TFD_MAX then
  begin
    ObSys(OB_CLOSE, r, 0, 0, 0, 0, 0);
    Result := -24; Exit;                                      { EMFILE }
  end;
  if (flags and $80000) <> 0 then ObSys(OB_FCNTL, r, 2, 1, 0, 0, 0);   { TFD_CLOEXEC }
  ObTfd[Integer(r)] := 1;
  if (flags and $800) <> 0 then ObTfd[Integer(r)] := ObTfd[Integer(r)] or 2;   { TFD_NONBLOCK }
  if clock = 0 then ObTfd[Integer(r)] := ObTfd[Integer(r)] or 4;
  Result := r;
end;

function ObTimerfdSettime(fd, flags, nv, ov: Int64): Int64;
var kv: array[0..3] of Int64; ts: array[0..1] of Int64;
    valNs, intNs, i: Int64;
begin
  if not ObIsTfd(fd) then begin Result := -LX_EINVAL; Exit; end;
  if nv = 0 then begin Result := -14; Exit; end;              { EFAULT }
  if ov <> 0 then for i := 0 to 3 do PInt64(ov + i * 8)^ := 0;
  intNs := PInt64(nv)^ * 1000000000 + PInt64(nv + 8)^;
  valNs := PInt64(nv + 16)^ * 1000000000 + PInt64(nv + 24)^;
  for i := 0 to 3 do kv[i] := 0;
  kv[0] := 1;                                                 { ident }
  PSmallInt(Int64(@kv[0]) + 8)^ := OB_EVFILT_TIMER;
  if valNs = 0 then
  begin                                                       { disarm }
    PWord(Int64(@kv[0]) + 10)^ := OB_EV_DELETE;
    ObSys(OB_KEVENT, fd, Int64(@kv[0]), 1, 0, 0, 0);
    Result := 0; Exit;
  end;
  if (flags and 1) <> 0 then                                  { TFD_TIMER_ABSTIME }
  begin
    if (ObTfd[Integer(fd)] and 4) <> 0 then ObSys(OB_CLOCK_GETTIME, 0, Int64(@ts[0]), 0, 0, 0, 0)
    else ObSys(OB_CLOCK_GETTIME, 3, Int64(@ts[0]), 0, 0, 0, 0);
    valNs := valNs - (ts[0] * 1000000000 + ts[1]);
    if valNs < 1 then valNs := 1;
  end;
  if intNs > 0 then
  begin
    PWord(Int64(@kv[0]) + 10)^ := OB_EV_ADD or OB_EV_ENABLE;
    kv[2] := intNs;
  end
  else
  begin
    PWord(Int64(@kv[0]) + 10)^ := OB_EV_ADD or OB_EV_ENABLE or OB_EV_ONESHOT;
    kv[2] := valNs;
  end;
  PInteger(Int64(@kv[0]) + 12)^ := OB_NOTE_NSECONDS;          { fflags }
  Result := Lx(ObSys(OB_KEVENT, fd, Int64(@kv[0]), 1, 0, 0, 0));
end;

{ read(timerfd): the expiration count as a u64, or EAGAIN when not fired
  and non-blocking. }
function ObTimerfdRead(fd, buf, len: Int64): Int64;
var kv: array[0..3] of Int64; ts: array[0..1] of Int64; r: Int64;
begin
  if len < 8 then begin Result := -LX_EINVAL; Exit; end;
  ts[0] := 0; ts[1] := 0;
  if (ObTfd[Integer(fd)] and 2) <> 0 then
    r := ObSys(OB_KEVENT, fd, 0, 0, Int64(@kv[0]), 1, Int64(@ts[0]))
  else
    r := ObSys(OB_KEVENT, fd, 0, 0, Int64(@kv[0]), 1, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if r = 0 then begin Result := -11; Exit; end;               { EAGAIN }
  PInt64(buf)^ := kv[2];
  Result := 8;
end;

{ ---- process odds and ends -------------------------------------------------- }

{ A wait status carries a signal number twice: the terminating signal in bits
  0..6, the stopping one in bits 8..15. The layout is Linux's, "continued"
  ($FFFF) included; only the numbers differ. }
function WaitStatusToLx(st: Int64): Int64;
var lo: Int64;
begin
  st := st and $FFFF;
  lo := st and $7F;
  if st = $FFFF then Result := st
  else if lo = $7F then Result := (LxSig((st shr 8) and $FF) shl 8) or $7F
  else if lo <> 0 then Result := (st and not Int64($7F)) or LxSig(lo)
  else Result := st;
end;

function ObWait4(pid, status, options, rusage: Int64): Int64;
var st, r: Int64;
begin
  st := 0;
  r := ObSys(OB_WAIT4, pid, Int64(@st), options and $B, rusage, 0, 0);   { WNOHANG WUNTRACED WCONTINUED agree }
  if (r > 0) and (status <> 0) then PInteger(status)^ := Integer(WaitStatusToLx(st));
  Result := Lx(r);
end;

{ rt_sigtimedwait -> __thrsigdivert(mask by value, info, timeout). Answers
  the LINUX signal number; a timeout is EAGAIN on both. }
function ObRtSigtimedwait(nset, info, ts: Int64): Int64;
var oi: array[0..16] of Int64;                                { OpenBSD siginfo_t, 136 B }
    r: Int64;
begin
  r := ObSys(OB_THRSIGDIVERT, MaskToOb(PInt64(nset)^), Int64(@oi[0]), ts, 0, 0, 0);
  if r > 0 then
  begin
    if info <> 0 then SiginfoToLx(Int64(@oi[0]), info);
    Result := LxSig(r);
  end
  else Result := Lx(r);
end;

{ times(): no OpenBSD syscall. struct tms in Linux's USER_HZ (100) from
  getrusage; the result is a monotonic tick count. }
function ObTimes(buf: Int64): Int64;
var ru: array[0..17] of Int64;     { struct rusage, 144 B on both }
    ts: array[0..1] of Int64;
begin
  if buf <> 0 then
  begin
    ObSys(OB_GETRUSAGE, 0, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf)^ := ru[0] * 100 + ru[1] div 10000;         { utime }
    PInt64(buf + 8)^ := ru[2] * 100 + ru[3] div 10000;     { stime }
    ObSys(OB_GETRUSAGE, -1, Int64(@ru[0]), 0, 0, 0, 0);
    PInt64(buf + 16)^ := ru[0] * 100 + ru[1] div 10000;    { cutime }
    PInt64(buf + 24)^ := ru[2] * 100 + ru[3] div 10000;    { cstime }
  end;
  ObSys(OB_CLOCK_GETTIME, 3, Int64(@ts[0]), 0, 0, 0, 0);
  Result := ts[0] * 100 + ts[1] div 10000000;
end;

{ OpenBSD struct statfs (568 B, measured) -> Linux struct statfs (120 B). }
function ObStatfs(nr, arg, lx: Int64): Int64;
var fs: array[0..71] of Int64;
    r, fl, ty, i, nm: Int64;
begin
  r := ObSys(nr, arg, Int64(@fs[0]), 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  for i := 0 to 14 do PInt64(lx + i * 8)^ := 0;
  nm := Int64(@fs[0]) + 120;                                  { f_fstypename }
  ty := 0;
  case PByte(nm)^ of                                          { Linux f_type magics }
    102: ty := $00011954;                                     { ffs }
    116: ty := $01021994;                                     { tmpfs }
    109: if PByte(nm + 1)^ = 102 then ty := $01021994         { mfs }
         else ty := $4D44;                                    { msdos }
    110: ty := $6969;                                         { nfs }
    99:  ty := $9660;                                         { cd9660 }
  end;
  PInt64(lx)^ := ty;
  PInt64(lx + 8)^ := PLongWord(Int64(@fs[0]) + 4)^;           { f_bsize }
  for i := 0 to 4 do PInt64(lx + 16 + i * 8)^ := fs[2 + i];   { blocks bfree bavail files ffree }
  PInt64(lx + 56)^ := fs[12];                                 { f_fsid }
  PInt64(lx + 64)^ := PLongWord(Int64(@fs[0]) + 104)^;        { f_namelen }
  PInt64(lx + 72)^ := PLongWord(Int64(@fs[0]) + 4)^;          { f_frsize }
  fl := PLongWord(Int64(@fs[0]))^;
  r := 0;
  if (fl and $1) <> 0 then r := r or 1;                       { ST_RDONLY }
  if (fl and $8) <> 0 then r := r or 2;                       { ST_NOSUID }
  if (fl and $10) <> 0 then r := r or 4;                      { ST_NODEV }
  if (fl and $4) <> 0 then r := r or 8;                       { ST_NOEXEC }
  if (fl and $2) <> 0 then r := r or 16;                      { ST_SYNCHRONOUS }
  if (fl and $8000) <> 0 then r := r or 1024;                 { ST_NOATIME }
  PInt64(lx + 80)^ := r;
  Result := 0;
end;

{ utimensat / futimens. UTIME_NOW/UTIME_OMIT are (1<<30)-1 / (1<<30)-2 on
  Linux, -2 / -1 on OpenBSD; a nil path means "the fd itself" on Linux only. }
function ObUtimensat(dirfd, path, times, flags: Int64): Int64;
var ts: array[0..3] of Int64;
    tp, i: Int64;
begin
  tp := 0;
  if times <> 0 then
  begin
    for i := 0 to 3 do ts[i] := PInt64(times + i * 8)^;
    for i := 0 to 1 do
      if ts[i * 2 + 1] = $3FFFFFFF then ts[i * 2 + 1] := -2
      else if ts[i * 2 + 1] = $3FFFFFFE then ts[i * 2 + 1] := -1;
    tp := Int64(@ts[0]);
  end;
  if path = 0 then Result := Lx(ObSys(OB_FUTIMENS, dirfd, tp, 0, 0, 0, 0))
  else Result := Lx(ObSys(OB_UTIMENSAT, dirfd, path, tp, ObAtFlags(flags), 0, 0));
end;

{ fallocate mode 0: OpenBSD has no preallocation at all, so the visible part
  of Linux's semantics -- a file that ends short of offset+len grows to it --
  is done with ftruncate. Other modes are EOPNOTSUPP, as on a Linux file
  system without them. }
function ObFallocate(fd, mode, off, len: Int64): Int64;
var sb: array[0..15] of Int64; r: Int64;
begin
  if mode <> 0 then begin Result := -95; Exit; end;
  if (off < 0) or (len <= 0) then begin Result := -LX_EINVAL; Exit; end;
  r := ObSys(OB_FSTAT, fd, Int64(@sb[0]), 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  if (PLongWord(@sb[0])^ and $F000) <> $8000 then begin Result := -19; Exit; end;   { not a regular file: ENODEV }
  if off + len > sb[10] then r := ObSys(OB_FTRUNCATE, fd, off + len, 0, 0, 0, 0)
  else r := 0;
  Result := Lx(r);
end;

var
  ObPersona: Int64;                         { personality(2): Linux's default PER_LINUX }

{ prctl: PR_SET_NAME (15) / PR_GET_NAME (16) -> setthrname / getthrname on
  this thread (tid 0). Any other option is EINVAL, as an unknown one is on
  Linux. }
function ObPrctl(op, arg: Int64): Int64;
var i: Integer;
begin
  case op of
    15: Result := Lx(ObSys(OB_SETTHRNAME, 0, arg, 0, 0, 0, 0));
    16: begin
          for i := 0 to 15 do PByte(arg + i)^ := 0;
          Result := Lx(ObSys(OB_GETTHRNAME, 0, arg, 16, 0, 0, 0));
        end;
  else
    Result := -LX_EINVAL;
  end;
end;

{ sched_getaffinity: OpenBSD has no CPU affinity; answer every online CPU
  (hw.ncpuonline), as an unrestricted Linux process sees. }
function ObGetAffinity(len, mask: Int64): Int64;
var mib: array[0..1] of Integer; n, sz, i: Int64; nc: Integer;
begin
  if len < 8 then begin Result := -LX_EINVAL; Exit; end;
  if len > 128 then len := 128;
  mib[0] := 6; mib[1] := 25;                                  { hw.ncpuonline }
  nc := 1; sz := 4;
  if ObSys(OB_SYSCTL, Int64(@mib[0]), 2, Int64(@nc), Int64(@sz), 0, 0) < 0 then nc := 1;
  for i := 0 to len - 1 do PByte(mask + i)^ := 0;
  n := nc;
  if n > len * 8 then n := len * 8;
  for i := 0 to n - 1 do
    PByte(mask + i div 8)^ := PByte(mask + i div 8)^ or (1 shl (i mod 8));
  Result := len;
end;

{ readlink("/proc/self/fd/N"). OpenBSD keeps no path for an open file, but
  a DIRECTORY's can be had: fchdir into it, getcwd, and fchdir back to a saved
  "." -- which is what crtl's fchdir and similar fd-to-path users need. Any
  other fd is ENOENT, as for a deleted file on Linux. -4096 = not that path. }
function ObProcFdLink(path, buf, cap: Int64): Int64;
var i, fd, here, r, n: Int64; tmp: array[0..1023] of Byte;
const Pre: array[0..13] of Byte = (47,112,114,111,99,47,115,101,108,102,47,102,100,47);   { /proc/self/fd/ }
      Dot: array[0..1] of Byte = (46, 0);
begin
  Result := -4096;
  if path = 0 then Exit;
  for i := 0 to 13 do
    if PByte(path + i)^ <> Pre[i] then Exit;
  fd := 0; i := 14;
  if (PByte(path + i)^ < 48) or (PByte(path + i)^ > 57) then Exit;
  while (PByte(path + i)^ >= 48) and (PByte(path + i)^ <= 57) do
  begin
    fd := fd * 10 + PByte(path + i)^ - 48; i := i + 1;
  end;
  if PByte(path + i)^ <> 0 then Exit;
  here := ObSys(OB_OPENAT, OB_AT_FDCWD, Int64(@Dot[0]), $20000 or $10000, 0, 0, 0);   { O_DIRECTORY|O_CLOEXEC }
  if here < 0 then begin Result := Lx(here); Exit; end;
  r := ObSys(OB_FCHDIR, fd, 0, 0, 0, 0, 0);
  if r < 0 then
  begin
    ObSys(OB_CLOSE, here, 0, 0, 0, 0, 0);
    if r = -9 then Result := -9 else Result := -LX_ENOENT;    { EBADF stays EBADF }
    Exit;
  end;
  r := ObSys(OB_GETCWD, Int64(@tmp[0]), 1024, 0, 0, 0, 0);
  ObSys(OB_FCHDIR, here, 0, 0, 0, 0, 0);
  ObSys(OB_CLOSE, here, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  n := StrLen0(Int64(@tmp[0]));
  if n > cap then n := cap;
  for i := 0 to n - 1 do PByte(buf + i)^ := tmp[i];
  Result := n;
end;

{ ---- ptys ----------------------------------------------------------------
  Linux: open /dev/ptmx, TIOCGPTN gives N, the slave is /dev/pts/N.
  OpenBSD: open /dev/ptm and PTMGET (_IOR('t',1,struct ptmget), 40 bytes:
  cfd, sfd, cn[16], sn[16]) hands back BOTH ends already open. The master is
  kept and the slave closed, so the slave is opened later by name as on Linux.
  N is the master's minor; OpenBSD's slave for minor m is /dev/tty +
  "pqrstuvwxyzPQRST"[m div 62] + "0-9a-zA-Z"[m mod 62] (measured on 8.0:
  minor 61 is ttypZ, and the stock /dev has only the 62 p-ptys). }
const
  DevPtmx: array[0..8] of Byte = (47,100,101,118,47,112,116,109,120);   { /dev/ptmx }
  DevPtm: array[0..8] of Byte = (47,100,101,118,47,112,116,109,0);      { /dev/ptm, NUL-terminated }
  DevPts: array[0..8] of Byte = (47,100,101,118,47,112,116,115,47);     { /dev/pts/ }
  PtyLetters: array[0..15] of Byte = (112,113,114,115,116,117,118,119,120,121,122,80,81,82,83,84);

function ObPtmx(flags: Int64): Int64;
var m, r: Int64; pg: array[0..4] of Int64;
begin
  m := ObSys(OB_OPENAT, OB_AT_FDCWD, Int64(@DevPtm[0]), 2 or $10000, 0, 0, 0);   { O_RDWR|O_CLOEXEC }
  if m < 0 then begin Result := Lx(m); Exit; end;
  r := ObSys(OB_IOCTL, m, $40287401, Int64(@pg[0]), 0, 0, 0);              { PTMGET }
  ObSys(OB_CLOSE, m, 0, 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  ObSys(OB_CLOSE, (pg[0] shr 32) and $FFFFFFFF, 0, 0, 0, 0, 0);            { sfd }
  Result := pg[0] and $FFFFFFFF;                                            { cfd }
  if (ObOpenFlags(flags) and 4) <> 0 then ObSys(OB_FCNTL, Result, 4, 4, 0, 0, 0);   { O_NONBLOCK }
  if (flags and $80000) <> 0 then ObSys(OB_FCNTL, Result, 2, 1, 0, 0, 0);          { O_CLOEXEC }
end;

{ The pty number of a master fd, or -ENOTTY for anything else. A master is a
  character device of major 6 (pty; the slaves are 5, tty). }
function ObPtyMinor(fd: Int64): Int64;
var st: array[0..15] of Int64; r, rdev: Int64;
begin
  r := ObSys(OB_FSTAT, fd, Int64(@st[0]), 0, 0, 0, 0);
  if r < 0 then begin Result := Lx(r); Exit; end;
  rdev := (st[3] shr 32) and $FFFFFFFF;                                     { st_rdev @28 }
  if ((st[0] and $F000) <> $2000) or (((rdev shr 8) and $FF) <> 6) then
    Result := -LX_ENOTTY
  else
    Result := (rdev and $FF) or ((rdev and $FFFF0000) shr 8);
end;

{ "/dev/pts/N" -> "/dev/ttyXY" in name (11 bytes, NUL-terminated); False if
  the path is not of that form. }
function ObPtsName(path, name: Int64): Boolean;
var i, n, c: Int64;
begin
  Result := False;
  if path = 0 then Exit;
  for i := 0 to 8 do
    if PByte(path + i)^ <> DevPts[i] then Exit;
  n := 0; i := 9;
  if (PByte(path + i)^ < 48) or (PByte(path + i)^ > 57) then Exit;
  while (PByte(path + i)^ >= 48) and (PByte(path + i)^ <= 57) and (n < 100000) do
  begin
    n := n * 10 + PByte(path + i)^ - 48; i := i + 1;
  end;
  if (PByte(path + i)^ <> 0) or (n >= 16 * 62) then Exit;
  for i := 0 to 7 do PByte(name + i)^ := DevPtm[i];                         { /dev/pt }
  PByte(name + 5)^ := 116; PByte(name + 6)^ := 116; PByte(name + 7)^ := 121;  { tty }
  PByte(name + 8)^ := PtyLetters[n div 62];
  c := n mod 62;
  if c < 10 then c := c + 48 else if c < 36 then c := c - 10 + 97 else c := c - 36 + 65;
  PByte(name + 9)^ := c;
  PByte(name + 10)^ := 0;
  Result := True;
end;

{ open/openat with the paths OpenBSD lacks. /dev/full is /dev/zero whose
  writes fail with ENOSPC (bit 3 of ObTfd marks the fd). }
function ObOpenAt(dirfd, path, flags, mode: Int64): Int64;
var nm: array[0..15] of Byte;
begin
  if PathIs(path, @ProcEnviron[0], Length(ProcEnviron)) then Result := ObProcEnviron
  else if PathIs(path, @DevPtmx[0], Length(DevPtmx)) then Result := ObPtmx(flags)
  else if ObPtsName(path, Int64(@nm[0])) then
    Result := Lx(ObSys(OB_OPENAT, OB_AT_FDCWD, Int64(@nm[0]), ObOpenFlags(flags), 0, 0, 0))
  else if PathIs(path, @ProcHostname[0], Length(ProcHostname)) then Result := ObProcHostname
  else if PathIs(path, @DevFull[0], Length(DevFull)) then
  begin
    Result := Lx(ObSys(OB_OPENAT, OB_AT_FDCWD, Int64(@DevZero[0]), ObOpenFlags(flags) and not Int64($E00), 0, 0, 0));
    if (Result >= 0) and (Result < OB_TFD_MAX) then ObTfd[Integer(Result)] := 8;
  end
  else Result := Lx(ObSys(OB_OPENAT, dirfd, path, ObOpenFlags(flags), mode, 0, 0));
end;

{ ---- the dispatcher ------------------------------------------------------- }

{$ifdef CPU_AARCH64}
function LxX64Call(nr, a0, a1, a2, a3, a4, a5: Int64): Int64;
{$else}
function PXXObsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
{$endif}
var sb: array[0..15] of Int64; t: array[0..3] of Int64; r, f, i, n: Int64;
begin
  case nr of
    0: if ObIsTfd(a0) then Result := ObTimerfdRead(a0, a1, a2)
       else Result := Lx(ObSys(OB_READ, a0, a1, a2, 0, 0, 0));
    1: if (a0 >= 0) and (a0 < OB_TFD_MAX) and ((ObTfd[Integer(a0)] and 8) <> 0) and (a2 > 0) then
         Result := -28                                          { /dev/full: ENOSPC }
       else Result := Lx(ObSys(OB_WRITE, a0, a1, a2, 0, 0, 0));
    2: Result := ObOpenAt(OB_AT_FDCWD, a0, a1, a2);
    257: Result := ObOpenAt(a0, a1, a2, a3);
    3: begin
         if (a0 >= 0) and (a0 < OB_TFD_MAX) then ObTfd[Integer(a0)] := 0;
         Result := Lx(ObSys(OB_CLOSE, a0, 0, 0, 0, 0, 0));
       end;
    4: Result := ObStatAt(OB_AT_FDCWD, a0, a1, 0);              { stat }
    5: begin                                                    { fstat }
         r := ObSys(OB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0);
         if r = 0 then StatToLinux(@sb[0], Pointer(a1));
         Result := Lx(r);
       end;
    6: Result := ObStatAt(OB_AT_FDCWD, a0, a1, $100);           { lstat }
    262: Result := ObStatAt(a0, a1, a2, a3);                    { newfstatat }
    332: begin                                                  { statx }
           if ((a2 and $1000) <> 0) and ((a1 = 0) or (PByte(a1)^ = 0)) then
             r := ObSys(OB_FSTAT, a0, Int64(@sb[0]), 0, 0, 0, 0)
           else
             r := ObSys(OB_FSTATAT, a0, a1, Int64(@sb[0]), ObAtFlags(a2), 0, 0);
           if r = 0 then StatToStatx(@sb[0], Pointer(a4));
           Result := Lx(r);
         end;
    7: Result := Lx(ObSys(OB_POLL, a0, a1, a2, 0, 0, 0));       { POLLIN..POLLNVAL bits are the same }
    8: Result := Lx(ObSys(OB_LSEEK, a0, a1, a2, 0, 0, 0));
    9: Result := Lx(ObSys(OB_MMAP, a0, a1, a2, ObMmapFlags(a3), a4, a5));
    10: Result := Lx(ObSys(OB_MPROTECT, a0, a1, a2, 0, 0, 0));
    11: Result := Lx(ObSys(OB_MUNMAP, a0, a1, 0, 0, 0, 0));
    12: Result := ObBrk(a0);
    16: case Integer(a1) of                                              { ioctl }
          $5401: begin                                          { TCGETS -> TIOCGETA }
                   r := ObSys(OB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if (r = 0) and (a2 <> 0) then TermiosToLx(Int64(@sb[0]), a2);
                   Result := Lx(r);
                 end;
          $5402, $5403, $5404: begin                            { TCSETS/W/F -> TIOCSETA/W/F }
                   TermiosToOb(a2, Int64(@sb[0]));
                   Result := Lx(ObSys(OB_IOCTL, a0, $802C7414 + (a1 - $5402), Int64(@sb[0]), 0, 0, 0));
                 end;
          $540B: begin                                          { TCFLSH -> TIOCFLUSH(FREAD/FWRITE) }
                   if (a2 < 0) or (a2 > 2) then Result := -LX_EINVAL
                   else
                   begin
                     t[0] := a2 + 1;
                     Result := Lx(ObSys(OB_IOCTL, a0, $80047410, Int64(@t[0]), 0, 0, 0));
                   end;
                 end;
          $5409: if a2 <> 0 then Result := Lx(ObSys(OB_IOCTL, a0, $2000745E, 0, 0, 0, 0))  { TCSBRK: drain }
                 else Result := 0;                              { (the 0.25 s break is not sent) }
          $540A: case Integer(a2) of                            { TCXONC }
                   0: Result := Lx(ObSys(OB_IOCTL, a0, $2000746F, 0, 0, 0, 0));   { TCOOFF -> TIOCSTOP }
                   1: Result := Lx(ObSys(OB_IOCTL, a0, $2000746E, 0, 0, 0, 0));   { TCOON -> TIOCSTART }
                 else Result := 0;
                 end;
          $5427: Result := Lx(ObSys(OB_IOCTL, a0, $2000747B, 0, 0, 0, 0));   { TIOCSBRK }
          -2147199952: begin                                    { $80045430 TIOCGPTN (the case is on Integer) }
                   r := ObPtyMinor(a0);
                   if r >= 0 then begin PInteger(a2)^ := Integer(r); Result := 0; end
                   else Result := r;
                 end;
          $40045431: begin                                      { TIOCSPTLCK: OpenBSD ptys have no lock }
                   r := ObPtyMinor(a0);
                   if r >= 0 then Result := 0 else Result := r;
                 end;
          $5428: Result := Lx(ObSys(OB_IOCTL, a0, $2000747A, 0, 0, 0, 0));   { TIOCCBRK }
          $5413: Result := Lx(ObSys(OB_IOCTL, a0, $40087468, a2, 0, 0, 0));  { TIOCGWINSZ }
          $541B: Result := Lx(ObSys(OB_IOCTL, a0, $4004667F, a2, 0, 0, 0));  { FIONREAD }
          $540E: Result := Lx(ObSys(OB_IOCTL, a0, $20007461, 0, 0, 0, 0));   { TIOCSCTTY }
          $540F, $5410: begin                                   { TIOCGPGRP / TIOCSPGRP }
                   { tty only: BSD pipes and sockets also accept these
                     (as the SIGIO owner), Linux answers ENOTTY }
                   r := ObSys(OB_IOCTL, a0, $402C7413, Int64(@sb[0]), 0, 0, 0);
                   if r = -25 then Result := -LX_ENOTTY
                   else if r < 0 then Result := Lx(r)
                   else if a1 = $540F then Result := Lx(ObSys(OB_IOCTL, a0, $40047477, a2, 0, 0, 0))
                   else Result := Lx(ObSys(OB_IOCTL, a0, $80047476, a2, 0, 0, 0));
                 end;
          $5411: Result := Lx(ObSys(OB_IOCTL, a0, $40047473, a2, 0, 0, 0));  { TIOCOUTQ }
          $5414: Result := Lx(ObSys(OB_IOCTL, a0, $80087467, a2, 0, 0, 0));  { TIOCSWINSZ }
          $5421: Result := Lx(ObSys(OB_IOCTL, a0, $8004667E, a2, 0, 0, 0));  { FIONBIO }
          $5422: Result := Lx(ObSys(OB_IOCTL, a0, $20007471, 0, 0, 0, 0));   { TIOCNOTTY }
          $5429: Result := Lx(ObSys(OB_IOCTL, a0, $40047463, a2, 0, 0, 0));  { TIOCGSID }
          $5450: Result := Lx(ObSys(OB_IOCTL, a0, $20006602, 0, 0, 0, 0));   { FIONCLEX }
          $5451: Result := Lx(ObSys(OB_IOCTL, a0, $20006601, 0, 0, 0, 0));   { FIOCLEX }
          $5452: Result := Lx(ObSys(OB_IOCTL, a0, $8004667D, a2, 0, 0, 0));  { FIOASYNC }
        else
          { unmapped: a bad fd is still EBADF, as the kernel would say first }
          if ObSys(OB_FCNTL, a0, 1, 0, 0, 0, 0) < 0 then Result := -9
          else Result := -LX_ENOTTY;
        end;
    17: Result := Lx(ObSys(OB_PREAD, a0, a1, a2, a3, 0, 0));
    18: Result := Lx(ObSys(OB_PWRITE, a0, a1, a2, a3, 0, 0));
    19: Result := Lx(ObSys(OB_READV, a0, a1, a2, 0, 0, 0));
    20: Result := Lx(ObSys(OB_WRITEV, a0, a1, a2, 0, 0, 0));
    21: Result := Lx(ObSys(OB_FACCESSAT, OB_AT_FDCWD, a0, a1, 0, 0, 0));
    269: begin                                                  { faccessat(2) }
           f := 0;
           if (a3 and $200) <> 0 then f := f or OB_AT_EACCESS;
           if (a3 and $100) <> 0 then f := f or OB_AT_SYMLINK_NOFOLLOW;
           Result := Lx(ObSys(OB_FACCESSAT, a0, a1, a2, f, 0, 0));
         end;
    439: begin
           f := 0;
           if (a3 and $200) <> 0 then f := f or OB_AT_EACCESS;
           if (a3 and $100) <> 0 then f := f or OB_AT_SYMLINK_NOFOLLOW;
           Result := Lx(ObSys(OB_FACCESSAT, a0, a1, a2, f, 0, 0));
         end;
    22: Result := Lx(ObSys(OB_PIPE2, a0, 0, 0, 0, 0, 0));
    293: Result := Lx(ObSys(OB_PIPE2, a0, ObOpenFlags(a1) and ($10000 or $4), 0, 0, 0, 0));
    23: Result := Lx(ObSys(OB_SELECT, a0, a1, a2, a3, a4, 0));
    24: Result := Lx(ObSys(OB_SCHED_YIELD, 0, 0, 0, 0, 0, 0));
    28: Result := Lx(ObSys(OB_MADVISE, a0, a1, a2, 0, 0, 0));
    32: Result := Lx(ObSys(OB_DUP, a0, 0, 0, 0, 0, 0));
    33: Result := Lx(ObSys(OB_DUP2, a0, a1, 0, 0, 0, 0));
    292: Result := Lx(ObSys(OB_DUP3, a0, a1, ObOpenFlags(a2) and $10000, 0, 0, 0));
    35: Result := Lx(ObSys(OB_NANOSLEEP, a0, a1, 0, 0, 0, 0));
    39: Result := ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0);
    186: Result := ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0);         { gettid }
    57, 58: begin                                               { fork, vfork }
              r := ObSys(OB_FORK, 0, 0, 0, 0, 0, 0);
              if (r >= 0) and (ObRdx <> 0) then r := 0;        { the child: rdx = 1 }
              Result := Lx(r);
            end;
    59: Result := Lx(ObSys(OB_EXECVE, a0, a1, a2, 0, 0, 0));
    60: begin ObExitThread(a0); Result := 0; end;
    231: begin ObSys(OB_EXIT, a0, 0, 0, 0, 0, 0); Result := 0; end;
    56: Result := ObClone(a0, a1, a2, a3, a5);
    202: Result := ObFutex(a0, a1, a2, a3, a4, a5);
    61: Result := ObWait4(a0, a1, a2, a3);
    62: begin
          f := ObSig(a1);
          if (f = 0) and (a1 <> 0) then Result := -LX_EINVAL
          else Result := Lx(ObSys(OB_KILL, a0, f, 0, 0, 0, 0));
        end;
    63: Result := ObUname(a0);
    72: begin                                                   { fcntl }
          case a1 of
            0, 1, 2: Result := Lx(ObSys(OB_FCNTL, a0, a1, a2, 0, 0, 0));
            3: begin
                 r := ObSys(OB_FCNTL, a0, 3, 0, 0, 0, 0);
                 if r < 0 then Result := Lx(r) else Result := LxOpenFlags(r);
               end;
            4: Result := Lx(ObSys(OB_FCNTL, a0, 4, ObOpenFlags(a2), 0, 0, 0));
            1030: Result := Lx(ObSys(OB_FCNTL, a0, 10, a2, 0, 0, 0));   { F_DUPFD_CLOEXEC }
          else
            Result := -LX_EINVAL;
          end;
        end;
    73: Result := Lx(ObSys(OB_FLOCK, a0, a1, 0, 0, 0, 0));
    74, 75: Result := Lx(ObSys(OB_FSYNC, a0, 0, 0, 0, 0, 0));
    76: Result := Lx(ObSys(OB_TRUNCATE, a0, a1, 0, 0, 0, 0));
    77: Result := Lx(ObSys(OB_FTRUNCATE, a0, a1, 0, 0, 0, 0));
    217: begin                                                  { getdents64 }
           r := ObSys(OB_GETDENTS, a0, a1, a2, 0, 0, 0);
           if r > 0 then DirentsToLinux(Pointer(a1), r);
           Result := Lx(r);
         end;
    79: begin                                                   { getcwd: Linux returns the length with the NUL }
          r := ObSys(OB_GETCWD, a0, a1, 0, 0, 0, 0);
          if r < 0 then Result := Lx(r) else Result := StrLen0(a0) + 1;
        end;
    80: Result := Lx(ObSys(OB_CHDIR, a0, 0, 0, 0, 0, 0));
    81: Result := Lx(ObSys(OB_FCHDIR, a0, 0, 0, 0, 0, 0));
    82: Result := Lx(ObSys(OB_RENAME, a0, a1, 0, 0, 0, 0));
    264: Result := Lx(ObSys(OB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    316: if a4 <> 0 then Result := -LX_EINVAL
         else Result := Lx(ObSys(OB_RENAMEAT, a0, a1, a2, a3, 0, 0));
    83: Result := Lx(ObSys(OB_MKDIR, a0, a1, 0, 0, 0, 0));
    258: Result := Lx(ObSys(OB_MKDIRAT, a0, a1, a2, 0, 0, 0));
    84: Result := Lx(ObSys(OB_RMDIR, a0, 0, 0, 0, 0, 0));
    86: Result := Lx(ObSys(OB_LINK, a0, a1, 0, 0, 0, 0));
    265: Result := Lx(ObSys(OB_LINKAT, a0, a1, a2, a3, ObAtFlags(a4), 0));
    87: Result := Lx(ObSys(OB_UNLINK, a0, 0, 0, 0, 0, 0));
    263: begin                                                  { unlinkat }
           f := 0;
           if (a2 and $200) <> 0 then f := OB_AT_REMOVEDIR;
           Result := Lx(ObSys(OB_UNLINKAT, a0, a1, f, 0, 0, 0));
         end;
    88: Result := Lx(ObSys(OB_SYMLINK, a0, a1, 0, 0, 0, 0));
    266: Result := Lx(ObSys(OB_SYMLINKAT, a0, a1, a2, 0, 0, 0));
    89: if PathIs(a0, @ProcExe[0], Length(ProcExe)) then Result := ObProcExe(a1, a2)
        else begin
          Result := ObProcFdLink(a0, a1, a2);
          if Result = -4096 then Result := Lx(ObSys(OB_READLINK, a0, a1, a2, 0, 0, 0));
        end;
    267: if PathIs(a1, @ProcExe[0], Length(ProcExe)) then Result := ObProcExe(a2, a3)
         else begin
           Result := ObProcFdLink(a1, a2, a3);
           if Result = -4096 then Result := Lx(ObSys(OB_READLINKAT, a0, a1, a2, a3, 0, 0));
         end;
    90: Result := Lx(ObSys(OB_CHMOD, a0, a1, 0, 0, 0, 0));
    91: Result := Lx(ObSys(OB_FCHMOD, a0, a1, 0, 0, 0, 0));
    268: Result := Lx(ObSys(OB_FCHMODAT, a0, a1, a2, 0, 0, 0));
    92: Result := Lx(ObSys(OB_CHOWN, a0, a1, a2, 0, 0, 0));
    93: Result := Lx(ObSys(OB_FCHOWN, a0, a1, a2, 0, 0, 0));
    94: Result := Lx(ObSys(OB_LCHOWN, a0, a1, a2, 0, 0, 0));
    260: Result := Lx(ObSys(OB_FCHOWNAT, a0, a1, a2, a3, ObAtFlags(a4), 0));
    95: Result := ObSys(OB_UMASK, a0, 0, 0, 0, 0, 0);
    96: Result := Lx(ObSys(OB_GETTIMEOFDAY, a0, a1, 0, 0, 0, 0));
    97: Result := ObGetRlimit(a0, a1);
    160: Result := ObSetRlimit(a0, a1);
    302: begin                                                  { prlimit64(0, res, new, old) }
           if (a0 <> 0) and (a0 <> ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0)) then
             Result := -LX_EINVAL
           else
           begin
             Result := 0;
             if a3 <> 0 then Result := ObGetRlimit(a1, a3);
             if (Result = 0) and (a2 <> 0) then Result := ObSetRlimit(a1, a2);
           end;
         end;
    98: Result := Lx(ObSys(OB_GETRUSAGE, a0, a1, 0, 0, 0, 0));  { struct rusage: same 144 B }
    102: Result := ObSys(OB_GETUID, 0, 0, 0, 0, 0, 0);
    104: Result := ObSys(OB_GETGID, 0, 0, 0, 0, 0, 0);
    107: Result := ObSys(OB_GETEUID, 0, 0, 0, 0, 0, 0);
    108: Result := ObSys(OB_GETEGID, 0, 0, 0, 0, 0, 0);
    105: Result := Lx(ObSys(OB_SETUID, a0, 0, 0, 0, 0, 0));
    106: Result := Lx(ObSys(OB_SETGID, a0, 0, 0, 0, 0, 0));
    109: Result := Lx(ObSys(OB_SETPGID, a0, a1, 0, 0, 0, 0));
    110: Result := ObSys(OB_GETPPID, 0, 0, 0, 0, 0, 0);
    111: Result := ObSys(OB_GETPGRP, 0, 0, 0, 0, 0, 0);
    112: Result := Lx(ObSys(OB_SETSID, 0, 0, 0, 0, 0, 0));
    121: Result := Lx(ObSys(OB_GETPGID, a0, 0, 0, 0, 0, 0));
    124: Result := Lx(ObSys(OB_GETSID, a0, 0, 0, 0, 0, 0));
    140: begin                                                  { getpriority: Linux returns 20 - nice }
           r := ObSys(OB_GETPRIORITY, a0, a1, 0, 0, 0, 0);
           if (r < 0) and (r >= -95) and (r <> -1) then Result := Lx(r)
           else Result := 20 - r;
         end;
    141: Result := Lx(ObSys(OB_SETPRIORITY, a0, a1, a2, 0, 0, 0));
    158: begin                                                  { arch_prctl }
           case a0 of
{$ifdef PXX_OBSD_LIBC}
             $1001, $1002: Result := ObSetBlock(a1);
{$else}
             $1001, $1002: Result := Lx(ObSys(OB_SET_TCB, a1, 0, 0, 0, 0, 0));   { SET_GS / SET_FS -> FS }
{$endif}
             $1003, $1004: begin                                { GET_FS / GET_GS }
                             PInt64(a1)^ := ObSys(OB_GET_TCB, 0, 0, 0, 0, 0, 0);
                             Result := 0;
                           end;
           else
             Result := -LX_EINVAL;
           end;
         end;
    201: begin                                                  { time }
           r := ObSys(OB_CLOCK_GETTIME, 0, Int64(@t[0]), 0, 0, 0, 0);
           if r < 0 then Result := Lx(r)
           else begin
             if a0 <> 0 then PInt64(a0)^ := t[0];
             Result := t[0];
           end;
         end;
    228: Result := Lx(ObSys(OB_CLOCK_GETTIME, ObClock(a0), a1, 0, 0, 0, 0));
    229: Result := Lx(ObSys(OB_CLOCK_GETRES, ObClock(a0), a1, 0, 0, 0, 0));
    230: if a1 = 0 then                                         { clock_nanosleep, relative }
           Result := Lx(ObSys(OB_NANOSLEEP, a2, a3, 0, 0, 0, 0))
         else
           Result := -LX_EINVAL;                                { TIMER_ABSTIME: not yet }
    280: Result := ObUtimensat(a0, a1, a2, a3);
    295: Result := Lx(ObSys(OB_PREADV, a0, a1, a2, a3, 0, 0));
    296: Result := Lx(ObSys(OB_PWRITEV, a0, a1, a2, a3, 0, 0));
    318: begin                                                  { getrandom: getentropy, 256 B per call }
           n := 0;
           while n < a1 do
           begin
             f := a1 - n;
             if f > 256 then f := 256;
             r := ObSys(OB_GETENTROPY, a0 + n, f, 0, 0, 0, 0);
             if r < 0 then begin n := Lx(r); Break; end;
             n := n + f;
           end;
           Result := n;
         end;
    41: begin                                                   { socket }
          { Linux's check order (__sys_socket[pair], __sock_create): stray
            flag bits in the type word, then the family, then the type. }
          f := ObAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL   { type 0..15, SOCK_CLOEXEC $80000, SOCK_NONBLOCK $800 }
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL            { SOCK_MAX = 11 }
          else Result := Lx(ObSys(OB_SOCKET, f, ObSockType(a1), a2, 0, 0, 0));
        end;
    42: Result := ObSockAddrCall(OB_CONNECT, a0, a1, a2);
    43: Result := ObSockAddrOut(OB_ACCEPT4, a0, a1, a2, 0);
    288: Result := ObSockAddrOut(OB_ACCEPT4, a0, a1, a2, a3);
    44: Result := ObSendto(a0, a1, a2, a3, a4, a5);
    45: Result := ObRecvfrom(a0, a1, a2, a3, a4, a5);
    46: Result := ObMsg(True, a0, a1, a2);
    47: Result := ObMsg(False, a0, a1, a2);
    48: Result := Lx(ObSys(OB_SHUTDOWN, a0, a1, 0, 0, 0, 0));
    49: Result := ObSockAddrCall(OB_BIND, a0, a1, a2);
    50: Result := Lx(ObSys(OB_LISTEN, a0, a1, 0, 0, 0, 0));
    51: Result := ObSockAddrOut(OB_GETSOCKNAME, a0, a1, a2, 0);
    52: Result := ObSockAddrOut(OB_GETPEERNAME, a0, a1, a2, 0);
    53: begin                                                   { socketpair }
          { Linux's check order (__sys_socket[pair], __sock_create): stray
            flag bits in the type word, then the family, then the type. }
          f := ObAf(a0);
          if (a1 and not Int64($8080F)) <> 0 then Result := -LX_EINVAL   { type 0..15, SOCK_CLOEXEC $80000, SOCK_NONBLOCK $800 }
          else if f < 0 then Result := -LX_EAFNOSUPPORT
          else if (a1 and $F) >= 11 then Result := -LX_EINVAL            { SOCK_MAX = 11 }
          else Result := Lx(ObSys(OB_SOCKETPAIR, f, ObSockType(a1), a2, a3, 0, 0));
        end;
    54: Result := ObSockopt(False, a0, a1, a2, a3, a4);
    55: Result := ObSockopt(True, a0, a1, a2, a3, a4);
    271: begin                                                  { ppoll: the mask is a u32 here }
           if a3 <> 0 then
           begin
             t[0] := MaskToOb(PInt64(a3)^);
             Result := Lx(ObSys(OB_PPOLL, a0, a1, a2, Int64(@t[0]), 0, 0));
           end
           else Result := Lx(ObSys(OB_PPOLL, a0, a1, a2, 0, 0, 0));
         end;
    270: begin                                                  { pselect6: a5 -> {sigset *, size} }
           if (a5 <> 0) and (PInt64(a5)^ <> 0) then
           begin
             t[0] := MaskToOb(PInt64(PInt64(a5)^)^);
             Result := Lx(ObSys(OB_PSELECT, a0, a1, a2, a3, a4, Int64(@t[0])));
           end
           else Result := Lx(ObSys(OB_PSELECT, a0, a1, a2, a3, a4, 0));
         end;
    213, 291: begin                                             { epoll_create, epoll_create1 }
                r := ObSys(OB_KQUEUE, 0, 0, 0, 0, 0, 0);
                if (r >= 0) and (nr = 291) and ((a0 and $80000) <> 0) then
                  ObSys(OB_FCNTL, r, 2, 1, 0, 0, 0);            { F_SETFD FD_CLOEXEC }
                Result := Lx(r);
              end;
    233: Result := ObEpollCtl(a0, a1, a2, a3);
    232, 281: Result := ObEpollWait(a0, a1, a2, a3);            { epoll_pwait: mask not applied }
    283: Result := ObTimerfdCreate(a0, a1);
    286: Result := ObTimerfdSettime(a0, a1, a2, a3);
    287: if ObIsTfd(a0) then                                    { timerfd_gettime: disarmed }
         begin
           for i := 0 to 3 do PInt64(a1 + i * 8)^ := 0;
           Result := 0;
         end
         else Result := -LX_EINVAL;
    128: Result := ObRtSigtimedwait(a0, a1, a2);
    100: Result := ObTimes(a0);
    137: Result := ObStatfs(OB_STATFS, a0, a1);
    138: Result := ObStatfs(OB_FSTATFS, a0, a1);
    113: Result := Lx(ObSys(OB_SETREUID, a0, a1, 0, 0, 0, 0));
    114: Result := Lx(ObSys(OB_SETREGID, a0, a1, 0, 0, 0, 0));
    115: Result := Lx(ObSys(OB_GETGROUPS, a0, a1, 0, 0, 0, 0));
    116: Result := Lx(ObSys(OB_SETGROUPS, a0, a1, 0, 0, 0, 0));
    117: Result := Lx(ObSys(OB_SETRESUID, a0, a1, a2, 0, 0, 0));
    118: Result := Lx(ObSys(OB_GETRESUID, a0, a1, a2, 0, 0, 0));
    119: Result := Lx(ObSys(OB_SETRESGID, a0, a1, a2, 0, 0, 0));
    120: Result := Lx(ObSys(OB_GETRESGID, a0, a1, a2, 0, 0, 0));
    133: Result := Lx(ObSys(OB_MKNOD, a0, a1, a2, 0, 0, 0));      { dev_t: same encoding for small numbers }
    259: Result := Lx(ObSys(OB_MKNODAT, a0, a1, a2, a3, 0, 0));
    135: begin                                                  { personality }
           Result := ObPersona;
           if a0 <> $FFFFFFFF then ObPersona := a0 and $FFFFFFFF;
         end;
    { sched_*: OpenBSD has no POSIX scheduling policies. Answer as Linux does
      for a SCHED_OTHER process, the only kind there is here: priority 0,
      and FIFO/RR refused as for a process without CAP_SYS_NICE. }
    142: if (a1 = 0) or (PInteger(a1)^ <> 0) then Result := -LX_EINVAL else Result := 0;
    143: if a1 = 0 then Result := -LX_EINVAL
         else begin PInteger(a1)^ := 0; Result := 0; end;
    144: case a1 and $3FFFFFFF of
           0, 3, 5: if (a2 = 0) or (PInteger(a2)^ <> 0) then Result := -LX_EINVAL else Result := 0;
           1, 2: Result := -1;                                  { EPERM }
         else Result := -LX_EINVAL;
         end;
    145: Result := 0;                                           { SCHED_OTHER }
    146: case a0 of 1, 2: Result := 99; 0, 3, 5: Result := 0; else Result := -LX_EINVAL; end;
    147: case a0 of 1, 2: Result := 1; 0, 3, 5: Result := 0; else Result := -LX_EINVAL; end;
    148: begin PInt64(a1)^ := 0; PInt64(a1 + 8)^ := 100000000; Result := 0; end;
    203: Result := 0;                                           { sched_setaffinity: nothing to restrict }
    204: Result := ObGetAffinity(a1, a2);
    149: Result := Lx(ObSys(OB_MLOCK, a0, a1, 0, 0, 0, 0));
    150: Result := Lx(ObSys(OB_MUNLOCK, a0, a1, 0, 0, 0, 0));
    151: Result := Lx(ObSys(OB_MLOCKALL, a0 and 3, 0, 0, 0, 0, 0));   { MCL_CURRENT/FUTURE agree }
    152: Result := Lx(ObSys(OB_MUNLOCKALL, 0, 0, 0, 0, 0, 0));
    157: Result := ObPrctl(a0, a1);
    162: begin ObSys(OB_SYNC, 0, 0, 0, 0, 0, 0); Result := 0; end;
    218: Result := ObSys(OB_GETTHRID, 0, 0, 0, 0, 0, 0);       { set_tid_address: the tid }
    227: Result := Lx(ObSys(OB_CLOCK_SETTIME, ObClock(a0), a1, 0, 0, 0, 0));
    235: Result := Lx(ObSys(OB_UTIMES, a0, a1, 0, 0, 0, 0));
    272: if a0 = 0 then Result := 0 else Result := -LX_EINVAL;  { unshare: nothing to unshare succeeds on Linux too }
    285: Result := ObFallocate(a0, a1, a2, a3);
    13: Result := ObRtSigaction(a0, a1, a2);
    14: Result := ObRtSigprocmask(a0, a1, a2);
    127: begin                                                  { rt_sigpending }
           r := ObSys(OB_SIGPENDING, 0, 0, 0, 0, 0, 0);
           if r < 0 then Result := Lx(r)
           else begin PInt64(a0)^ := MaskToLx(r and $FFFFFFFF); Result := 0; end;
         end;
    130: Result := Lx(ObSys(OB_SIGSUSPEND, MaskToOb(PInt64(a0)^), 0, 0, 0, 0, 0));
    34: Result := Lx(ObSys(OB_SIGSUSPEND, ObCurMask, 0, 0, 0, 0, 0));   { pause }
    131: Result := ObSigaltstack(a0, a1);
    200: Result := ObThrKill(a0, a1);                           { tkill }
    234: if (a0 <> ObSys(OB_GETPID, 0, 0, 0, 0, 0, 0)) and (a0 > 0) then
           Result := -3                                         { ESRCH: not our process }
         else Result := ObThrKill(a1, a2);                      { tgkill }
    36: Result := Lx(ObSys(OB_GETITIMER, a0, a1, 0, 0, 0, 0)); { struct itimerval: same }
    38: Result := Lx(ObSys(OB_SETITIMER, a0, a1, a2, 0, 0, 0));
    37: begin                                                   { alarm }
          for i := 0 to 3 do t[i] := 0;
          t[2] := a0;
          for i := 0 to 3 do sb[i] := 0;
          r := ObSys(OB_SETITIMER, 0, Int64(@t[0]), Int64(@sb[0]), 0, 0, 0);
          if r < 0 then Result := Lx(r)
          else begin
            Result := sb[2];
            if sb[3] > 0 then Result := Result + 1;
          end;
        end;
  else
    Result := -LX_ENOSYS;
  end;
end;

{$ifdef CPU_AARCH64}
{$I lxa64front.inc}

var
  ObTlsSet: Boolean;

{ The main thread's thread pointer is written with msr by the compiler's
  entry code. OpenBSD/arm64 does not save tpidr_el0 when it switches a
  thread out; it reloads it from pcb_tcb, which stays 0 until __set_tcb.
  So the first call after the entry code ran tells the kernel, once, as
  nbsdabi does with _lwp_setprivate. (A switch between the entry's msr and
  this call would lose the register; the window is a few instructions.)
  Threads get theirs from __tfork's tf_tcb. }
function PXXObsdSyscall(nr, a0, a1, a2, a3, a4, a5: Int64): Int64; cdecl;
begin
  if not ObTlsSet then
    if Int64(__pxxTlsBase) <> 0 then
    begin
      ObTlsSet := True;
      ObSys(OB_SET_TCB, Int64(__pxxTlsBase), 0, 0, 0, 0, 0);
    end;
  Result := LxA64Front(nr, a0, a1, a2, a3, a4, a5);
end;
{$endif}

end.
