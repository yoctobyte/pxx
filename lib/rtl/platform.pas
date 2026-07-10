{ SPDX-License-Identifier: Zlib }
unit platform;
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

  PAL_NET_AF_INET = 2;
  PAL_NET_SOCK_STREAM = 1;
  PAL_NET_SOCK_DGRAM = 2;

  PAL_NET_IP_ANY = 0;
  PAL_NET_IP_LOOPBACK = $7F000001;

  PAL_NET_EAGAIN = -11;
  PAL_NET_EWOULDBLOCK = -11;
  PAL_NET_EINPROGRESS = -115;
  PAL_NET_ECONNREFUSED = -111;
  PAL_NET_ECONNRESET = -104;
  PAL_NET_ETIMEDOUT = -110;

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
  PAL_OPEN_DIRECTORY = $10000;

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
function PalMkdir(path: PChar; mode: Integer): Integer;
function PalRmdir(path: PChar): Integer;
function PalGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalStat(path: PChar; var info: TPalFileStat): Integer;
function PalStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
function PalFstat(handle: Integer; var info: TPalFileStat): Integer;
function PalLstat(path: PChar; var info: TPalFileStat): Integer;
function PalFcntl(handle, cmd: Integer; arg: Int64): Integer;
function PalFsync(handle: Integer): Integer;
function PalFchmod(handle, mode: Integer): Integer;
function PalFtruncate(handle: Integer; length: Int64): Integer;
function PalAccess(path: PChar; mode: Integer): Integer;
function PalFchown(handle, owner, group: Integer): Integer;
function PalGeteuid: Integer;
function PalReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
function PalGetpid: Integer;
function PalGetcwd(buf: PChar; size: Integer): Integer;
function PalNanosleep(sec, nsec: Int64): Integer;
function PalRealtime(var sec, nsec: Int64): Integer;
function PalUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
function PalMmapAnon(len: Int64): Pointer;
function PalMunmap(addr: Pointer; len: Int64): Integer;

function PalSocket(domain, kind, proto: Integer): Integer;
function PalSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
function PalSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalListen(handle, backlog: Integer): Integer;
function PalAccept(handle: Integer): Integer;
function PalRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalShutdown(handle, how: Integer): Integer;
function PalSocketClose(handle: Integer): Integer;
function PalSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
function PalRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
function PalPoll(handle, events, timeoutMs: Integer): Integer;
function PalGetSockError(handle: Integer): Integer;
function PalGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;

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

function PalRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
begin
  Result := PalBackendRecvFromIpv4(handle, buf, len, outAddr, outPort);
end;

function PalPoll(handle, events, timeoutMs: Integer): Integer;
begin
  Result := PalBackendPoll(handle, events, timeoutMs);
end;

function PalGetSockError(handle: Integer): Integer;
begin
  Result := PalBackendGetSockError(handle);
end;

function PalGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PalBackendGetSockNameIpv4(handle, outAddr, outPort);
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
