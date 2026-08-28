{ SPDX-License-Identifier: Zlib }
unit platform_backend;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ WASI PAL backend, selected by -Fulib/rtl/platform/wasi.

  WHY A THIRD BACKEND RATHER THAN AN ARM OF THE POSIX ONE. The posix backend
  reaches the kernel through `__pxxrawsyscall` and a per-architecture table of
  Linux syscall NUMBERS. wasm has no syscall instruction and no number space:
  a host call is an IMPORT, named by module and field, resolved at
  instantiation. There is nothing to add a `{$ifdef CPU_WASM32}` block to —
  the mechanism differs, not the constants. Before this file existed, every
  program that touched a file failed at PARSE time with `undefined variable
  (SYS_openat)`, because posix is the compiled-in default PAL and wasm32 fell
  into it.

  The seam is the one ESP already proved: `platform.pas` says `uses
  platform_backend`, and whichever backend directory is on the unit search
  path supplies it. So this needs no compiler change — pass
  `-Fulib/rtl/platform/wasi` and wasm32 binds here instead.

  WASI IS NOT A UNIX, and the shape of the gap is different from ESP's. ESP
  has no processes, so fork/exec/wait/kill are refused there. WASI preview1
  additionally has:

    * no process creation at all (same refusals as ESP, for a different
      reason: the ABI simply has no such call);
    * no sockets in preview1 proper (sock_accept exists, sock_send/sock_recv
      operate on already-open descriptors a host handed in; there is no
      socket(), no connect(), no bind());
    * CAPABILITY-BASED paths. There is no `open(path)`. A program may only
      reach directories the host PREOPENED for it, and every path operation is
      relative to one of those descriptors — `path_open(dirfd, ..., path)`.
      Resolving an absolute path means finding which preopen it falls under,
      which is bookkeeping this backend does and posix never has to;
    * no getuid/getgid/chmod/chown — the model has no users;
    * no mmap. Linear memory grows with `memory.grow` and nothing else.

  A refusal here returns PAL_ERR_UNSUPPORTED, exactly as ESP's does: a
  POSIX-shaped program meets a clear error rather than a wrong answer. That
  failure mode is deliberate and is the whole reason to write the refusals out
  rather than let the unit fail to compile. }

interface

uses platform_types;

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;
function PalBackendDlOpen(name: PChar): Pointer;
function PalBackendDlSym(handle: Pointer; sym: PChar): Pointer;
function PalBackendDlClose(handle: Pointer): Integer;
function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
function PalBackendFlush(handle: Integer): Integer;
function PalBackendClose(handle: Integer): Integer;
function PalBackendIgnoreSignal(sig: Integer): Integer;
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
function PalBackendFsync(handle: Integer): Integer;
function PalBackendFchmod(handle, mode: Integer): Integer;
function PalBackendChmod(path: PChar; mode: Integer): Integer;
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
function PalBackendMmapAnon(len: Int64): Pointer;
function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
function PalBackendMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
function PalBackendSocket(domain, kind, proto: Integer): Integer;
function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;
function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
function PalBackendGetSockError(handle: Integer): Integer;
function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Integer;
function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;
function PalBackendVfork: Integer;
function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalBackendDup2(oldFd, newFd: Integer): Integer;
function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalBackendKill(pid, sig: Integer): Integer;
function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

{ Redeclared rather than imported: platform.pas `uses` this unit, so this unit
  cannot `uses` platform.pas. Same duplication the ESP backend carries, for the
  same reason. }
const
  PAL_ERR_UNSUPPORTED = -38;   { Linux ENOSYS, the portable "not here" }

function PalBackendPlatform: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendHasFiles: Boolean;
begin
  Result := False;
end;

function PalBackendHasSockets: Boolean;
begin
  Result := False;
end;

function PalBackendHasThreads: Boolean;
begin
  Result := False;
end;

function PalBackendHasDynlib: Boolean;
begin
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
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFlush(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendClose(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendIgnoreSignal(sig: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendDelete(path: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRename(oldPath, newPath: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMkdir(path: PChar; mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRmdir(path: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendChdir(path: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSymlink(target, linkpath: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendLink(oldPath, newPath: PChar): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFcntl(handle, cmd: Integer; arg: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFsync(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFchmod(handle, mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendChmod(path: PChar; mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendUmask(mask: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFtruncate(handle: Integer; length: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAccess(path: PChar; mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFchown(handle, owner, group: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGeteuid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetuid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetgid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetegid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetppid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetpid: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendNanosleep(sec, nsec: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRealtime(var sec, nsec: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMmapAnon(len: Int64): Pointer;
begin
  Result := nil;
end;

function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
begin
  Result := nil;
end;

function PalBackendMprotect(addr: Pointer; len: Int64; prot: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMunmap(addr: Pointer; len: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendListen(handle, backlog: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAccept(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendShutdown(handle, how: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSocketClose(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer; const addr: TPalIn6Addr; port, scopeId: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSockError(handle: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMonotonicMillis: Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

procedure PalBackendYield;
begin
end;

function PalBackendVfork: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendDup2(oldFd, newFd: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendKill(pid, sig: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

end.
