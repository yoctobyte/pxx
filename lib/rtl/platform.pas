{ SPDX-License-Identifier: Zlib }
unit platform;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Minimal Platform Abstraction Layer (PAL).

  This facade is platform-neutral. The implementation is selected by putting one
  backend directory (for example lib/rtl/platform/posix or lib/rtl/platform/esp)
  on the Pascal unit search path so `uses platform_backend` binds there. }

interface

uses platform_types, platform_backend;

const
  PAL_STDIN  = 0;
  PAL_STDOUT = 1;
  PAL_STDERR = 2;

  PAL_PLATFORM_POSIX = 1;
  PAL_PLATFORM_ESP_IDF = 2;

  PAL_NET_AF_UNIX = 1;        { Linux AF_UNIX/AF_LOCAL — filesystem sockets }
  PAL_NET_AF_INET = 2;
  PAL_NET_AF_INET6 = 10;      { Linux AF_INET6 }
  PAL_NET_SOCK_STREAM = 1;
  PAL_NET_SOCK_DGRAM = 2;

  PAL_NET_IP_ANY = 0;
  PAL_NET_IP_LOOPBACK = $7F000001;

  { setsockopt level/name for IPV6_V6ONLY, for a caller that wants to pin
    whether a `::` listener also accepts v4. Linux values, taken from a gcc
    probe rather than from memory. }
  PAL_NET_IPPROTO_IPV6 = 41;
  PAL_NET_IPV6_V6ONLY = 26;

  PAL_NET_EAGAIN = -11;
  PAL_NET_EWOULDBLOCK = -11;
  PAL_NET_EINPROGRESS = -115;
  PAL_NET_ECONNREFUSED = -111;
  PAL_NET_ECONNRESET = -104;
  PAL_NET_ETIMEDOUT = -110;
  PAL_NET_ENOTSUP = -95;      { EOPNOTSUPP — the backend has no such facility }
  PAL_NET_ENAMETOOLONG = -36; { a socket path that does not fit sun_path }

  { Readiness poll event/result bits (Linux poll(2) values, shared across PAL
    arches). PalPoll returns the OR of the revents bits that fired. }
  PAL_POLL_IN  = $001;
  PAL_POLL_OUT = $004;
  PAL_POLL_ERR = $008;
  PAL_POLL_HUP = $010;
  PAL_POLL_NVAL = $020;

  PAL_SHUT_RD = 0;
  PAL_SHUT_WR = 1;
  PAL_SHUT_RDWR = 2;

  PAL_OPEN_READ   = 0;
  PAL_OPEN_WRITE  = 1;
  PAL_OPEN_RDWR   = 2;
  PAL_OPEN_CREATE = $40;
  PAL_OPEN_EXCL   = $80;
  PAL_OPEN_TRUNC  = $200;
  PAL_OPEN_APPEND = $400;
{ O_DIRECTORY is one of the few open() flags Linux does NOT define uniformly
  across architectures: it is 0200000 ($10000) on x86-64 / i386 / riscv32 but
  0100000... no -- 040000 ($4000) on arm and aarch64, which swap it with
  O_DIRECT. Measured on each target rather than taken from a header, including
  the negative control (opening a regular FILE with the correct flag must give
  ENOTDIR).

  Getting it wrong is wrong in BOTH directions, which is why it went unnoticed:
  on ARM the x86 value made PalOpen return EINVAL for a real directory, and it
  made opening a regular file SUCCEED where the flag should have rejected it.
  The whole directory-listing surface was dead on arm32 and aarch64.

  The other flags here (CREATE/EXCL/TRUNC/APPEND) are uniform on every Linux
  target we build for, and were checked rather than assumed. }
{$if defined(CPU_ARM32) or defined(CPU_AARCH64)}
  PAL_OPEN_DIRECTORY = $4000;
{$else}
  PAL_OPEN_DIRECTORY = $10000;
{$endif}

  PAL_DIRENT_UNKNOWN = 0;
  PAL_DIRENT_FILE    = 8;
  PAL_DIRENT_DIR     = 4;

  PAL_SEEK_SET = 0;
  PAL_SEEK_CUR = 1;
  PAL_SEEK_END = 2;

  PAL_ERR_UNSUPPORTED = -38; { Linux ENOSYS, used as the portable "not here" }

function PalPlatform: Integer;
function PalHasFiles: Boolean;
function PalHasSockets: Boolean;
function PalHasThreads: Boolean;
function PalHasDynlib: Boolean;

{ Dynamic loader (policy: libc-free default -> honest nil/0 stubs; posix with
  -dPXX_DYNLIB_LIBC -> dlopen/dlsym/dlclose. PalHasDynlib reports which). }
function PalDlOpen(name: PChar): Pointer;
function PalDlSym(handle: Pointer; sym: PChar): Pointer;
function PalDlClose(handle: Pointer): Integer;

function PalUnsupported: Integer;

function PalOpen(path: PChar; flags, mode: Integer): Integer;
function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
function PalTell(handle: Integer): Int64;
function PalFlush(handle: Integer): Integer;
function PalClose(handle: Integer): Integer;
function PalDelete(path: PChar): Integer;
function PalRename(oldPath, newPath: PChar): Integer;

const
  PAL_SIGINT  = 2;    { Ctrl-C }
  PAL_SIGPIPE = 13;   { write to a closed peer }
  PAL_SIGTERM = 15;   { kill / shutdown }

{ Set a signal to be ignored (SIG_IGN). This is the safe, restorer-free case —
  the kernel never invokes a handler, so no signal-return trampoline is needed.
  Networking code ignores SIGPIPE so a closed peer yields an error, not death.
  Returns 0 on success. No-op (0) on platforms without POSIX signals (ESP). }
function PalIgnoreSignal(sig: Integer): Integer;
function PalMkdir(path: PChar; mode: Integer): Integer;
function PalRmdir(path: PChar): Integer;
{ Change the process working directory. Process-GLOBAL: it affects every
  subsequent relative path in the program, including other threads. }
function PalChdir(path: PChar): Integer;
{ Create a symbolic link at linkpath pointing at target, and a hard link
  respectively. ESP has neither and reports PAL_ERR_UNSUPPORTED. }
function PalSymlink(target, linkpath: PChar): Integer;
function PalLink(oldPath, newPath: PChar): Integer;
function PalGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalStat(path: PChar; var info: TPalFileStat): Integer;
function PalStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
function PalFstat(handle: Integer; var info: TPalFileStat): Integer;
function PalLstat(path: PChar; var info: TPalFileStat): Integer;
function PalFcntl(handle, cmd: Integer; arg: Int64): Integer;
function PalFsync(handle: Integer): Integer;
function PalFchmod(handle, mode: Integer): Integer;
function PalChmod(path: PChar; mode: Integer): Integer;
function PalUmask(mask: Integer): Integer;
function PalFtruncate(handle: Integer; length: Int64): Integer;
function PalAccess(path: PChar; mode: Integer): Integer;
function PalFchown(handle, owner, group: Integer): Integer;
function PalGeteuid: Integer;
function PalGetuid: Integer;
function PalGetgid: Integer;
function PalGetegid: Integer;
function PalGetppid: Integer;
function PalReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
function PalGetpid: Integer;
function PalGetcwd(buf: PChar; size: Integer): Integer;
function PalNanosleep(sec, nsec: Int64): Integer;
function PalRealtime(var sec, nsec: Int64): Integer;
function PalUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
function PalMmapAnon(len: Int64): Pointer;
{ Anonymous mapping with an EXPLICIT protection, for callers that need
  executable pages (PROT_READ|WRITE|EXEC = 7). PalMmapAnon stays read/write. }
function PalMmapAnonProt(len: Int64; prot: Integer): Pointer;
function PalMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
function PalMunmap(addr: Pointer; len: Int64): Integer;

function PalSocket(domain, kind, proto: Integer): Integer;
function PalSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
function PalSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;

{ Connect an AF_UNIX stream socket to a filesystem path (a `sockaddr_un`).
  `path` is a pathname socket — the abstract namespace (a leading NUL) is not
  offered, because nothing here needs it and it would make the length rules
  subtler. Paths longer than 107 bytes do not fit sun_path and are refused
  rather than silently truncated to a DIFFERENT existing socket.

  POSIX only: the ESP backend has no AF_UNIX and returns PAL_NET_ENOTSUP. }
function PalConnectUnix(handle: Integer; const path: string): Integer;

{ IPv6 bind/connect. `addr` is the 16 address bytes in WIRE order — an IPv6
  address is already a byte string, so unlike the IPv4 LongWord there is nothing
  to byte-swap. `scopeId` is the interface index a link-local address (fe80::/10)
  needs to be routable; pass 0 for global and loopback addresses, where the
  kernel ignores it. }
function PalBindIpv6(handle: Integer; const addr: TPalIn6Addr;
                     port, scopeId: Integer): Integer;
function PalConnectIpv6(handle: Integer; const addr: TPalIn6Addr;
                        port, scopeId: Integer): Integer;

{ The IPv6 loopback, ::1 — the IPv6 counterpart of PAL_NET_IP_LOOPBACK. }
function PalIn6Loopback: TPalIn6Addr;

{ The unspecified address, :: — bind to it to accept on every interface. }
function PalIn6Any: TPalIn6Addr;
function PalListen(handle, backlog: Integer): Integer;
function PalAccept(handle: Integer): Integer;
function PalRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalShutdown(handle, how: Integer): Integer;
function PalSocketClose(handle: Integer): Integer;
function PalSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
function PalRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
function PalSendToIpv6(handle: Integer; buf: Pointer; len: Integer;
                       const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
function PalRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer;
                         var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
function PalPoll(handle, events, timeoutMs: Integer): Integer;
{ Set-shaped readiness poll: fds points at nfds C `struct pollfd` records (int
  fd, short events, short revents — 8 bytes, the layout PalPoll already packs
  for its single entry), and revents are written back IN PLACE. Returns the
  number of ready descriptors, 0 on timeout, or -errno.

  This is not a loop over PalPoll and cannot be: the point of a set poll is to
  block on the WHOLE set at once, and calling the single-handle form per entry
  either blocks on the first one or busy-spins the rest. Backs C's poll(). }
function PalPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
function PalGetSockError(handle: Integer): Integer;
function PalGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
function PalIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
function PalAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr;
                       var outPort, outScopeId: Integer): Integer;

function PalMonotonicMillis: Int64;
procedure PalYield;

function PalVfork: Integer;
function PalExecve(path: PChar; argv, envp: Pointer): Integer;
function PalPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalDup2(oldFd, newFd: Integer): Integer;
function PalWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalKill(pid, sig: Integer): Integer;
function PalVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

function PalPlatform: Integer;
begin
  Result := PalBackendPlatform;
end;

function PalGetuid: Integer;
begin
  Result := PalBackendGetuid;
end;

function PalGetgid: Integer;
begin
  Result := PalBackendGetgid;
end;

function PalGetegid: Integer;
begin
  Result := PalBackendGetegid;
end;

function PalGetppid: Integer;
begin
  Result := PalBackendGetppid;
end;

function PalChdir(path: PChar): Integer;
begin
  Result := PalBackendChdir(path);
end;

function PalSymlink(target, linkpath: PChar): Integer;
begin
  Result := PalBackendSymlink(target, linkpath);
end;

function PalLink(oldPath, newPath: PChar): Integer;
begin
  Result := PalBackendLink(oldPath, newPath);
end;

function PalHasFiles: Boolean;
begin
  Result := PalBackendHasFiles;
end;

function PalHasSockets: Boolean;
begin
  Result := PalBackendHasSockets;
end;

function PalHasThreads: Boolean;
begin
  Result := PalBackendHasThreads;
end;

function PalHasDynlib: Boolean;
begin
  Result := PalBackendHasDynlib;
end;

function PalDlOpen(name: PChar): Pointer;
begin
  Result := PalBackendDlOpen(name);
end;

function PalDlSym(handle: Pointer; sym: PChar): Pointer;
begin
  Result := PalBackendDlSym(handle, sym);
end;

function PalDlClose(handle: Pointer): Integer;
begin
  Result := PalBackendDlClose(handle);
end;

function PalUnsupported: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := PalBackendOpen(path, flags, mode);
end;

function PalRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendRead(handle, buf, len);
end;

function PalWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendWrite(handle, buf, len);
end;

function PalSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
begin
  Result := PalBackendSeek(handle, offset, whence);
end;

function PalTell(handle: Integer): Int64;
begin
  Result := PalSeek(handle, 0, PAL_SEEK_CUR);
end;

function PalFlush(handle: Integer): Integer;
begin
  Result := PalBackendFlush(handle);
end;

function PalClose(handle: Integer): Integer;
begin
  Result := PalBackendClose(handle);
end;

function PalIgnoreSignal(sig: Integer): Integer;
begin
  Result := PalBackendIgnoreSignal(sig);
end;

function PalDelete(path: PChar): Integer;
begin
  Result := PalBackendDelete(path);
end;

function PalRename(oldPath, newPath: PChar): Integer;
begin
  Result := PalBackendRename(oldPath, newPath);
end;

function PalMkdir(path: PChar; mode: Integer): Integer;
begin
  Result := PalBackendMkdir(path, mode);
end;

function PalRmdir(path: PChar): Integer;
begin
  Result := PalBackendRmdir(path);
end;

function PalGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendGetDents64(handle, buf, len);
end;

function PalStat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PalBackendStat(path, info);
end;

function PalStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PalBackendStatAt(dirHandle, path, info);
end;

function PalFstat(handle: Integer; var info: TPalFileStat): Integer;
begin
  Result := PalBackendFstat(handle, info);
end;

function PalLstat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PalBackendLstat(path, info);
end;

function PalFcntl(handle, cmd: Integer; arg: Int64): Integer;
begin
  Result := PalBackendFcntl(handle, cmd, arg);
end;

function PalFsync(handle: Integer): Integer;
begin
  Result := PalBackendFsync(handle);
end;

function PalChmod(path: PChar; mode: Integer): Integer;
begin
  Result := PalBackendChmod(path, mode);
end;

function PalUmask(mask: Integer): Integer;
begin
  Result := PalBackendUmask(mask);
end;

function PalFchmod(handle, mode: Integer): Integer;
begin
  Result := PalBackendFchmod(handle, mode);
end;

function PalFtruncate(handle: Integer; length: Int64): Integer;
begin
  Result := PalBackendFtruncate(handle, length);
end;

function PalAccess(path: PChar; mode: Integer): Integer;
begin
  Result := PalBackendAccess(path, mode);
end;

function PalFchown(handle, owner, group: Integer): Integer;
begin
  Result := PalBackendFchown(handle, owner, group);
end;

function PalGeteuid: Integer;
begin
  Result := PalBackendGeteuid;
end;

function PalReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  Result := PalBackendReadlink(path, buf, bufsz);
end;

function PalGetpid: Integer;
begin
  Result := PalBackendGetpid;
end;

function PalGetcwd(buf: PChar; size: Integer): Integer;
begin
  Result := PalBackendGetcwd(buf, size);
end;

function PalNanosleep(sec, nsec: Int64): Integer;
begin
  Result := PalBackendNanosleep(sec, nsec);
end;

function PalRealtime(var sec, nsec: Int64): Integer;
begin
  Result := PalBackendRealtime(sec, nsec);
end;

function PalUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
begin
  Result := PalBackendUtimes(path, atimeSec, mtimeSec);
end;

function PalMmapAnonProt(len: Int64; prot: Integer): Pointer;
begin
  Result := PalBackendMmapAnonProt(len, prot);
end;

function PalMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
begin
  Result := PalBackendMprotect(addr, len, prot);
end;

function PalMmapAnon(len: Int64): Pointer;
begin
  Result := PalBackendMmapAnon(len);
end;

function PalMunmap(addr: Pointer; len: Int64): Integer;
begin
  Result := PalBackendMunmap(addr, len);
end;

function PalSocket(domain, kind, proto: Integer): Integer;
begin
  Result := PalBackendSocket(domain, kind, proto);
end;

function PalSetSocketReuseAddr(handle, enabled: Integer): Integer;
begin
  Result := PalBackendSetSocketReuseAddr(handle, enabled);
end;

function PalSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
begin
  Result := PalBackendSetSockOpt(handle, level, optname, valPtr, valLen);
end;

function PalSetSocketNonBlocking(handle, enabled: Integer): Integer;
begin
  Result := PalBackendSetSocketNonBlocking(handle, enabled);
end;

function PalBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
begin
  Result := PalBackendBindIpv4(handle, hostAddr, port);
end;

function PalConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
begin
  Result := PalBackendConnectIpv4(handle, hostAddr, port);
end;

function PalConnectUnix(handle: Integer; const path: string): Integer;
begin
  Result := PalBackendConnectUnix(handle, path);
end;

function PalBindIpv6(handle: Integer; const addr: TPalIn6Addr;
                     port, scopeId: Integer): Integer;
begin
  Result := PalBackendBindIpv6(handle, addr, port, scopeId);
end;

function PalConnectIpv6(handle: Integer; const addr: TPalIn6Addr;
                        port, scopeId: Integer): Integer;
begin
  Result := PalBackendConnectIpv6(handle, addr, port, scopeId);
end;

function PalIn6Loopback: TPalIn6Addr;
var i: Integer;
begin
  for i := 0 to 15 do Result.Bytes[i] := 0;
  Result.Bytes[15] := 1;                      { ::1 }
end;

function PalIn6Any: TPalIn6Addr;
var i: Integer;
begin
  for i := 0 to 15 do Result.Bytes[i] := 0;   { :: }
end;

function PalListen(handle, backlog: Integer): Integer;
begin
  Result := PalBackendListen(handle, backlog);
end;

function PalAccept(handle: Integer): Integer;
begin
  Result := PalBackendAccept(handle);
end;

function PalRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendRecv(handle, buf, len);
end;

function PalSend(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PalBackendSend(handle, buf, len);
end;

function PalShutdown(handle, how: Integer): Integer;
begin
  Result := PalBackendShutdown(handle, how);
end;

function PalSocketClose(handle: Integer): Integer;
begin
  Result := PalBackendSocketClose(handle);
end;

function PalSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
begin
  Result := PalBackendSendToIpv4(handle, buf, len, hostAddr, port);
end;

function PalSendToIpv6(handle: Integer; buf: Pointer; len: Integer;
                       const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
begin
  Result := PalBackendSendToIpv6(handle, buf, len, addr, port, scopeId);
end;

function PalRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer;
                         var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
begin
  Result := PalBackendRecvFromIpv6(handle, buf, len, outAddr, outPort, outScopeId);
end;

function PalAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr;
                       var outPort, outScopeId: Integer): Integer;
begin
  Result := PalBackendAcceptIpv6(handle, outAddr, outPort, outScopeId);
end;

function PalRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
begin
  Result := PalBackendRecvFromIpv4(handle, buf, len, outAddr, outPort);
end;

function PalPoll(handle, events, timeoutMs: Integer): Integer;
begin
  Result := PalBackendPoll(handle, events, timeoutMs);
end;

function PalPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
begin
  Result := PalBackendPollSet(fds, nfds, timeoutMs);
end;

function PalGetSockError(handle: Integer): Integer;
begin
  Result := PalBackendGetSockError(handle);
end;

function PalGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PalBackendGetSockNameIpv4(handle, outAddr, outPort);
end;

function PalGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PalBackendGetPeerNameIpv4(handle, outAddr, outPort);
end;

function PalGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
begin
  Result := PalBackendGetSockOpt(handle, level, optname, valPtr, lenPtr);
end;

function PalIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
begin
  Result := PalBackendIoctl(handle, cmd, argp);
end;

function PalAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PalBackendAcceptIpv4(handle, outAddr, outPort);
end;

function PalMonotonicMillis: Int64;
begin
  Result := PalBackendMonotonicMillis;
end;

procedure PalYield;
begin
  PalBackendYield;
end;

function PalVfork: Integer;
begin
  Result := PalBackendVfork;
end;

function PalExecve(path: PChar; argv, envp: Pointer): Integer;
begin
  Result := PalBackendExecve(path, argv, envp);
end;

function PalPipe2(var pipefd: array of Integer; flags: Integer): Integer;
begin
  Result := PalBackendPipe2(pipefd, flags);
end;

function PalDup2(oldFd, newFd: Integer): Integer;
begin
  Result := PalBackendDup2(oldFd, newFd);
end;

function PalWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := PalBackendWait4(pid, wstatus, options, rusage);
end;

function PalKill(pid, sig: Integer): Integer;
begin
  Result := PalBackendKill(pid, sig);
end;

function PalVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
begin
  Result := PalBackendVforkAndExec(path, argv, envp, stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd);
end;

end.
