{ SPDX-License-Identifier: Zlib }
unit platform_backend;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP-IDF/FreeRTOS PAL backend selected by -Fulib/rtl/platform/esp. }

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
function PalBackendUtimensat(dirFd: Integer; path: PChar;
                             aSec, aNsec, mSec, mNsec: Int64;
                             flags: Integer): Integer;
function PalBackendFsync(handle: Integer): Integer;
function PalBackendFdatasync(handle: Integer): Integer;
function PalBackendFchmod(handle, mode: Integer): Integer;
function PalBackendChmod(path: PChar; mode: Integer): Integer;
function PalBackendChown(path: PChar; owner, group: Integer): Integer;
function PalBackendLchown(path: PChar; owner, group: Integer): Integer;
function PalBackendPrlimit(resource: Integer; newLim, oldLim: Pointer): Integer;
function PalBackendGetrusage(who: Integer; usage: Pointer): Integer;
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
function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr;
                            port, scopeId: Integer): Integer;
function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr;
                               port, scopeId: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;
function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer; flags: Integer): Int64;
function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer; flags: Integer): Int64;
function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer;
                              const addr: TPalIn6Addr; port, scopeId: Integer; flags: Integer): Int64;
function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer;
                                var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer; flags: Integer): Int64;
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

uses newliberrno;

const
  PAL_STDIN  = 0;
  PAL_STDOUT = 1;
  PAL_STDERR = 2;
  PAL_PLATFORM_ESP_IDF = 2;
  PAL_ERR_UNSUPPORTED = -38;

  PAL_OPEN_READ   = 0;
  PAL_OPEN_WRITE  = 1;
  PAL_OPEN_RDWR   = 2;
  PAL_OPEN_CREATE = $40;
  PAL_OPEN_EXCL   = $80;
  PAL_OPEN_TRUNC  = $200;
  PAL_OPEN_APPEND = $400;
  PAL_OPEN_DIRECTORY = $10000;

  PAL_NET_AF_INET = 2;
  PAL_NET_ENOTSUP = -95;   { lwIP has no AF_UNIX }
  { the same values as platform.pas's PAL_NET_*, which this unit cannot see
    (platform uses it); they are the PAL contract's Linux numbers }
  PAL_NET_ECONNRESET = -104;
  PAL_NET_ECONNREFUSED = -111;
  { lwIP's numbering (lwip/sockets.h), NOT Linux's. These were 1 / 2 / 4, the
    Linux values, from the first cut of this unit: every SO_REUSEADDR set and
    every SO_ERROR read on ESP asked lwIP for an option that does not exist
    and got -1. The Pascal wifi-ap example ignores that return, so nothing
    showed it until mimic_socket raised on it (2026-09-25, on the S3). }
  SOL_SOCKET = $FFF;
  SO_REUSEADDR = $0004;
  SO_ERROR = $1007;
  F_SETFL = 4;
  { NEWLIB's value, because IDF compiles lwIP against newlib's <fcntl.h> and
    lwIP's own `#define O_NONBLOCK 1` is only a fallback that never applies
    there. It was 1: in newlib that is O_WRONLY, which lwip_fcntl's F_SETFL
    masks off as an access-mode bit before it looks, so every
    PalSetSocketNonBlocking(h, 1) on ESP set the socket BLOCKING and returned
    0. Measured on the S3, 2026-09-25: a non-blocking listen socket's accept
    blocked forever with nothing pending. The xtensa and riscv32 toolchains
    both preprocess O_NONBLOCK to 0x4000. }
  O_NONBLOCK = $4000;

type
  PB = ^Byte;

{$ifdef CPU_XTENSA}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}

{$ifdef PXX_PAL_ESP_IDF_TARGET}
procedure vTaskDelay(ticks: Integer); external;
function usleep(us: LongWord): Integer; external;   { esp_libc }
function esp_timer_get_time: Int64; external;

function fopen(path: PChar; mode: PChar): Pointer; cdecl; external;
function fread(ptr: Pointer; size, nmemb: Integer; stream: Pointer): Integer; cdecl; external;
function fwrite(ptr: Pointer; size, nmemb: Integer; stream: Pointer): Integer; cdecl; external;
function fclose(stream: Pointer): Integer; cdecl; external;
function fflush(stream: Pointer): Integer; cdecl; external;
function fseek(stream: Pointer; offset, whence: Integer): Integer; cdecl; external;
function ftell(stream: Pointer): Integer; cdecl; external;
function remove(path: PChar): Integer; cdecl; external;
function rename(oldPath, newPath: PChar): Integer; cdecl; external;
function mkdir(path: PChar; mode: Integer): Integer; cdecl; external;
function rmdir(path: PChar): Integer; cdecl; external;

function lwip_socket(domain, kind, protocol: Integer): Integer; cdecl; external;
function lwip_setsockopt(s, level, optname: Integer; optval: Pointer; optlen: Integer): Integer; cdecl; external;
function lwip_fcntl(s, cmd, val: Integer): Integer; cdecl; external;
function lwip_bind(s: Integer; name: Pointer; namelen: Integer): Integer; cdecl; external;
function lwip_connect(s: Integer; name: Pointer; namelen: Integer): Integer; cdecl; external;
function lwip_listen(s, backlog: Integer): Integer; cdecl; external;
function lwip_accept(s: Integer; addr: Pointer; addrlen: Pointer): Integer; cdecl; external;
function lwip_recv(s: Integer; mem: Pointer; len, flags: Integer): Integer; cdecl; external;
function lwip_send(s: Integer; data: Pointer; len, flags: Integer): Integer; cdecl; external;
function lwip_shutdown(s, how: Integer): Integer; cdecl; external;
function lwip_close(s: Integer): Integer; cdecl; external;
function lwip_sendto(s: Integer; data: Pointer; size, flags: Integer; toAddr: Pointer; tolen: Integer): Integer; cdecl; external;
function lwip_recvfrom(s: Integer; mem: Pointer; len, flags: Integer; fromAddr: Pointer; fromlen: Pointer): Integer; cdecl; external;
function lwip_poll(fds: Pointer; nfds, timeout: Integer): Integer; cdecl; external;
function lwip_getsockopt(s, level, optname: Integer; optval: Pointer; optlen: Pointer): Integer; cdecl; external;
function lwip_getsockname(s: Integer; name: Pointer; namelen: Pointer): Integer; cdecl; external;
function lwip_getpeername(s: Integer; name: Pointer; namelen: Pointer): Integer; cdecl; external;
function lwip_ioctl(s: Integer; cmd: LongWord; argp: Pointer): Integer; cdecl; external;

{ ERRNO, IN THE NUMBERING THE PAL PROMISES. The PAL's contract is -errno in
  LINUX numbering (PAL_NET_ETIMEDOUT = -110, and the POSIX backend hands back
  the raw syscall result), so a caller can compare against PAL_NET_* and a
  NilPy OSError can carry CPython's number. lwIP and newlib report a failure
  as -1 and leave the cause in NEWLIB's errno, whose numbering is NOT Linux's
  for 69 names (ETIMEDOUT is 116 there), so this backend used to return a
  bare -1 and every socket error read "[Errno 1]". The translation is
  compiler/builtin/newliberrno.pas -- ONE generated table, shared with NilPy's
  file I/O. This unit carried its own copy while the table lived in pypal,
  which a Pascal ESP program cannot link (it needs the builtin string
  helpers); INERT UNDER A PIN OLDER THAN THE ONE THAT CARRIES newliberrno. }
function __errno: PInteger; cdecl; external;


{ A lwIP return: itself when it succeeded, else -errno (Linux numbering). }
function EspNet(rc: Integer): Integer;
var e: Integer;
begin
  if rc >= 0 then begin EspNet := rc; Exit; end;
  e := __errno^;
  if e <= 0 then EspNet := rc   { no cause recorded: keep lwIP's own value }
  else EspNet := -NewlibToLinuxErrno(e);
end;
{$endif}

{ lwIP/BSD sockaddr_in: byte 0 = sin_len, byte 1 = sin_family (NOT the Linux
  2-byte sin_family at offset 0 the POSIX backend uses). port (offset 2-3) and
  addr (offset 4-7) are network byte order and identical to the Linux layout. }
procedure FillSockAddrIpv4(sa: Pointer; hostAddr: LongWord; port: Integer);
var i: Integer;
begin
  for i := 0 to 15 do PB(Pointer(Int64(sa) + i))^ := 0;
  PB(Pointer(Int64(sa) + 0))^ := 16;             { sin_len = sizeof(sockaddr_in) }
  PB(Pointer(Int64(sa) + 1))^ := PAL_NET_AF_INET; { sin_family }
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
  Result := PAL_PLATFORM_ESP_IDF;
end;

function PalBackendHasFiles: Boolean;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := True;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := False;
{$endif}
end;

function PalBackendHasSockets: Boolean;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := True;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := False;
{$endif}
end;

function PalBackendHasThreads: Boolean;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := True;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := False;
{$endif}
end;

function PalBackendHasDynlib: Boolean;
begin
  Result := False;
end;

{ No dynamic loader on ESP — honest stubs (mirrors the posix no-define shape). }
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

function PalBackendOpen(path: PChar; flags, mode: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var stream: Pointer;
begin
  if (flags and PAL_OPEN_EXCL) <> 0 then
  begin
    Result := PAL_ERR_UNSUPPORTED;
    Exit;
  end;
  if (flags and PAL_OPEN_DIRECTORY) <> 0 then
  begin
    Result := PAL_ERR_UNSUPPORTED;
    Exit;
  end;

  stream := nil;
  if (flags and PAL_OPEN_APPEND) <> 0 then
  begin
    if (flags and PAL_OPEN_RDWR) = PAL_OPEN_RDWR then
      stream := fopen(path, PChar('a+b'))
    else
      stream := fopen(path, PChar('ab'));
  end
  else if (flags and PAL_OPEN_TRUNC) <> 0 then
  begin
    if (flags and PAL_OPEN_RDWR) = PAL_OPEN_RDWR then
      stream := fopen(path, PChar('w+b'))
    else
      stream := fopen(path, PChar('wb'));
  end
  else if (flags and PAL_OPEN_CREATE) <> 0 then
  begin
    if (flags and PAL_OPEN_RDWR) = PAL_OPEN_RDWR then
      stream := fopen(path, PChar('r+b'))
    else
      stream := fopen(path, PChar('rb+'));
    if stream = nil then
      stream := fopen(path, PChar('w+b'));
  end
  else if (flags and PAL_OPEN_RDWR) = PAL_OPEN_RDWR then
    stream := fopen(path, PChar('r+b'))
  else if (flags and PAL_OPEN_WRITE) = PAL_OPEN_WRITE then
    stream := fopen(path, PChar('rb+'))
  else
    stream := fopen(path, PChar('rb'));

  if stream = nil then
    Result := -1
  else
    Result := Integer(stream);
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

{ THE STANDARD STREAMS GO THROUGH picolibc's putchar/getchar, not a refusal.
  fd 0/1/2 are not VFS fds under IDF (esp_libc stores whatever fd open()
  returned in its stdin/stdout streams, so write(1, ..) is EBADF), which is why
  this arm used to answer PAL_ERR_UNSUPPORTED -- and that silenced every C
  printf on ESP, since crtl's stdout reaches the console only through here
  (measured 2026-09-24: a printf hello on esp32c3 booted, returned from
  app_main and printed nothing). Pascal's WriteLn never came this way: it
  reaches the same putchar through builtinheap's PXXIdfStdWrite/PXXIdfStdRead,
  which this mirrors byte for byte. Those are implementation-private to the
  builtin unit, so this is a second spelling of one policy: change both. }
{$ifdef PXX_PAL_ESP_IDF_TARGET}
function PalIdfPutchar(c: Integer): Integer; cdecl; external name 'putchar';
function PalIdfGetchar: Integer; cdecl; external name 'getchar';
{$endif}

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var n, c: Integer; p: PByte;
begin
  if handle = PAL_STDIN then
  begin
    p := PByte(buf);
    n := 0;
    while n < len do
    begin
      c := PalIdfGetchar;
      if c < 0 then Break;          { EOF: what was read so far, 0 = EOF }
      p[n] := Byte(c);
      Inc(n);
      if c = 10 then Break;         { a line at a time, as a tty read returns }
    end;
    Result := n;
  end
  else if handle <= PAL_STDERR then
    Result := PAL_ERR_UNSUPPORTED
  else
    Result := fread(buf, 1, len, Pointer(handle));
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var i: Integer; p: PByte;
begin
  if (handle = PAL_STDOUT) or (handle = PAL_STDERR) then
  begin
    p := PByte(buf);
    for i := 0 to len - 1 do
      if PalIdfPutchar(p[i]) < 0 then
      begin
        Result := -1;
        Exit;
      end;
    Result := len;
  end
  else if handle <= PAL_STDERR then
    Result := PAL_ERR_UNSUPPORTED
  else
    Result := fwrite(buf, 1, len, Pointer(handle));
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendSeek(handle: Integer; offset: Int64; whence: Integer): Int64;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  if handle <= PAL_STDERR then
  begin
    Result := PAL_ERR_UNSUPPORTED;
    Exit;
  end;
  if fseek(Pointer(handle), Integer(offset), whence) < 0 then
    Result := -1
  else
    Result := ftell(Pointer(handle));
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendFlush(handle: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  if handle <= PAL_STDERR then
    Result := PAL_ERR_UNSUPPORTED
  else
    Result := fflush(Pointer(handle));
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendClose(handle: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  if handle <= PAL_STDERR then
  begin
    Result := PAL_ERR_UNSUPPORTED;
    Exit;
  end;
  { A file handle here IS a FILE* from fopen, cast to Integer. An lwip socket fd
    is a small integer from the VFS. crtl has ONE close(), so a C program doing
    sockets AND file I/O reaches this with either
    (bug-b-crtl-esp-close-cannot-dispatch-socket-vs-file), and fclose() of a
    small integer dereferences a null-page address — undefined behaviour, from a
    plausible-looking call.

    This does NOT solve the dispatch: telling the two spaces apart properly
    needs the PAL to own the handle namespace, and confirming they ARE
    distinguishable on real IDF needs hardware nobody has run this against. What
    it does is refuse the case that is certainly not a FILE*, because no
    platform puts a valid pointer in the first page. So the failure mode becomes
    PAL_ERR_UNSUPPORTED — the deliberate Track S refusal — instead of memory
    corruption. }
  if handle < 4096 then
  begin
    Result := PAL_ERR_UNSUPPORTED;
    Exit;
  end;
  Result := fclose(Pointer(handle));
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendIgnoreSignal(sig: Integer): Integer;
begin
  Result := 0;   { FreeRTOS has no POSIX signals — nothing to ignore }
end;

function PalBackendDelete(path: PChar): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := remove(path);
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRename(oldPath, newPath: PChar): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := rename(oldPath, newPath);
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendMkdir(path: PChar; mode: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := mkdir(path, mode);
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRmdir(path: PChar): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := rmdir(path);
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ ESP-IDF's VFS has no working directory and no hard/symbolic links, so these
  are refused rather than faked — a chdir that silently did nothing would make
  every later relative path wrong. }
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

procedure ClearPalFileStat(var info: TPalFileStat);
begin
  info.Size := -1;
  info.MTimeSec := 0;
  info.Mode := 0;
  info.IsDir := False;
  info.IsFile := False;
  info.Nlink := 1;      { a plain file has one link }
  info.Uid := 0;
  info.Gid := 0;
  info.Rdev := 0;
  info.ATimeSec := 0;
  info.CTimeSec := 0;
end;

function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
begin
  ClearPalFileStat(info);
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;
begin
  ClearPalFileStat(info);
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFstat(handle: Integer; var info: TPalFileStat): Integer;
begin
  ClearPalFileStat(info);
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendLstat(path: PChar; var info: TPalFileStat): Integer;
begin
  ClearPalFileStat(info);
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

function PalBackendFdatasync(handle: Integer): Integer;
{ ESP-IDF's VFS has no data-only sync: a SPIFFS/FAT flush is all-or-nothing.
  Aliasing this onto PalBackendFsync would be a different call wearing this
  name, so it refuses -- POSIX-shaped code meets PAL_ERR_UNSUPPORTED rather
  than a wrong answer, which is this platform's whole contract. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ FreeRTOS has no sync(2): there is no global buffer cache to flush, so this joins the deliberate-refusal set rather than pretending to succeed. }
function PalBackendSync: Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetsid: Integer;
{ FreeRTOS gives TASKS, not processes: there is no session and no process
  group for setsid to create, and no supplementary-group list for getgroups to
  report. Refusing is the honest answer -- see the 33 other deliberate refusals
  in this file. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetGroups(count: Integer; list: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetPriority(which, who: Integer): Integer;
{ FreeRTOS has task priorities, but they are not nice values and there is no
  process/pgrp/user to select with `which'. Answering with a task priority
  would be a different quantity under the same name. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetPriority(which, who, prio: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetSid(pid: Integer): Integer;
{ No sessions -- the same reason setsid refuses just above. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRawSyscall(num, a1, a2, a3, a4, a5, a6: NativeInt): NativeInt;
{ FreeRTOS has no syscall interface at all: the PAL entries above reach IDF
  functions, not a kernel trap table, so there is no number to pass on. A
  program asking for syscall(2) here has assumed a kernel that is not present. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendClockSetTime(clockId: Integer; sec, nsec: Int64): Integer;
{ FreeRTOS has no settable system clock behind this interface; the RTC is set through IDF, not a syscall. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendUtimensat(dirFd: Integer; path: PChar;
                             aSec, aNsec, mSec, mNsec: Int64;
                             flags: Integer): Integer;
{ FreeRTOS's VFS has no timestamp-setting call behind this interface. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendFchmod(handle, mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ ESP is not a Unix: FreeRTOS/SPIFFS has no permission bits and no per-process
  file-creation mask, so these are refused loudly rather than faked. Same
  treatment as fchmod right above. }
function PalBackendChmod(path: PChar; mode: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ Same refusal as chmod right above, and for the same reason: there is no
  ownership model here to change. Refused loudly rather than faked. }
function PalBackendChown(path: PChar; owner, group: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendLchown(path: PChar; owner, group: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendTruncate(path: PChar; length: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ FreeRTOS gives tasks, not processes, so there is no user/sys/children
  accounting to report. Refused rather than answering zeros, which a shell
  would print as a plausible "0m0.000s". }
function PalBackendTimes(buf: Pointer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ There is no kernel here to name itself. Refused rather than inventing a
  sysname, which would make a version check silently take a Linux branch. }
function PalBackendUname(buf: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ FreeRTOS has no per-process resource limits -- there are no processes.
  Refused rather than answering RLIM_INFINITY, which would tell a caller it
  may open unlimited descriptors on a device that has very few. }
function PalBackendPrlimit(resource: Integer; newLim, oldLim: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ FreeRTOS has no per-process accounting -- there are no processes. Refused rather than answering zeros, which
  would read as a program that used no CPU. }
function PalBackendGetrusage(who: Integer; usage: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ No device nodes and no FIFOs here -- refused rather than faked. }
function PalBackendMknod(path: PChar; mode: Integer; dev: Int64): Integer;
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
  Result := 0;
end;

{ ESP has no users or process hierarchy; 0 is the honest answer for a system
  with exactly one privilege level, matching what PalBackendGeteuid reports. }
function PalBackendGetuid: Integer;
begin
  Result := 0;
end;

function PalBackendGetgid: Integer;
begin
  Result := 0;
end;

function PalBackendGetegid: Integer;
begin
  Result := 0;
end;

function PalBackendGetppid: Integer;
begin
  Result := 0;
end;

function PalBackendReadlink(path: PChar; buf: Pointer; bufsz: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetpid: Integer;
begin
  Result := 1;
end;

function PalBackendGetcwd(buf: PChar; size: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendNanosleep(sec, nsec: Int64): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var us, chunk: Int64;
begin
  { ESP-IDF's usleep (esp_libc/src/time.c): vTaskDelay for whole ticks, with
    the monotonic clock making sure at least `us` has passed, and
    esp_rom_delay_us below one tick. So a sleep of a tick or more YIELDS, and
    the idle task and the task watchdog get their turn.

    This returned PAL_ERR_UNSUPPORTED until 2026-09-24, so on ESP `time.sleep`
    and sysutils.Sleep neither waited nor yielded. A NilPy program pacing
    itself with time.sleep(0.02) ran flat out and was killed by the task
    watchdog (IDLE0 starved), found by examples/esp32/adc-s3. Demos until
    then paced with esptimer.sleep_ms, which is why nothing had shown it.
    usleep takes a 32-bit count, hence the chunks. }
  us := sec * 1000000 + nsec div 1000;
  while us > 0 do
  begin
    chunk := us;
    if chunk > 1000000000 then
      chunk := 1000000000;
    usleep(LongWord(chunk));
    us := us - chunk;
  end;
  Result := 0;
end;
{$else}
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendRealtime(var sec, nsec: Int64): Integer;
begin
  sec := 0; nsec := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;

{ THE MONOTONIC CLOCKS ARE ANSWERED, THE WALL CLOCK IS REFUSED. esp_timer
  counts microseconds since boot and never steps, which is exactly what
  CLOCK_MONOTONIC (1), CLOCK_MONOTONIC_RAW (4) and CLOCK_BOOTTIME (7) mean.
  PalBackendMonotonicMillis below already reads it. Until 2026-09-24 this
  refused every id, so time.monotonic() / perf_counter() on ESP returned 0.0
  while the RTL's own millisecond clock worked (found by
  examples/esp32/adc-s3, whose timing rows read 0). Wall-clock time
  (CLOCK_REALTIME and the rest) has no source until something like SNTP sets
  one, so it still gets PAL_ERR_UNSUPPORTED rather than a wrong answer,
  as PalBackendRealtime does. Zeroing the outputs first means a caller that
  ignores the result reads 0, not whatever was on its stack. }
function PalBackendClockGetTime(clockId: Integer; var sec, nsec: Int64): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var us: Int64;
{$endif}
begin
  sec := 0; nsec := 0;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  if (clockId = 1) or (clockId = 4) or (clockId = 7) then
  begin
    us := esp_timer_get_time;
    sec := us div 1000000;
    nsec := (us mod 1000000) * 1000;
    Result := 0;
    Exit;
  end;
{$endif}
  Result := PAL_ERR_UNSUPPORTED;
end;

{ FreeRTOS gives TASKS, not processes, so there is nothing here to exit -- and
  the honest answer is a refusal the caller can see rather than a halt loop that
  looks like a hang. The interface says a backend that cannot terminate returns
  PAL_ERR_UNSUPPORTED and therefore RETURNS, which is what this does. }
function PalBackendExit(code: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRandomBytes(buf: Pointer; n: Integer): Integer;
begin
  { REFUSES DELIBERATELY, and this is the one entry where refusing is not a gap.
    ESP has no getrandom: entropy comes from the HW RNG register, which
    random.pas reaches as TIER 1 (__pxxHwRandom64) before it ever asks the OS.
    Answering PAL_ERR_UNSUPPORTED routes ESP to the tier it already uses, while
    a 0 here would hand a caller an unfilled buffer it was told to trust.
    33 other PAL entries refuse for the same class of reason -- FreeRTOS gives
    tasks, not processes -- so POSIX-shaped code meets a defined `not here`
    instead of a wrong answer. }
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendUtimes(path: PChar; atimeSec, mtimeSec: Int64): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendMmapAnon(len: Int64): Pointer;
begin
  Result := Pointer(-1);
end;

{ ESP has no MMU and no anonymous mapping to hand out — same refusal as
  PalBackendMmapAnon above. A JIT is not a thing here: code runs from flash or
  from IRAM the IDF allocates, neither of which this call can produce, so
  answering with a fake pointer would be a wrong answer rather than a missing
  feature. }
function PalBackendMmapAnonProt(len: Int64; prot: Integer): Pointer;
begin
  Result := Pointer(-1);
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
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_socket(domain, kind, proto));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
var one: Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  one := enabled;
  Result := EspNet(lwip_setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, @one, 4));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSetSockOpt(handle, level, optname: Integer; valPtr: Pointer; valLen: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_setsockopt(handle, level, optname, valPtr, valLen));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
var flags: Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  if enabled <> 0 then flags := O_NONBLOCK else flags := 0;
  Result := EspNet(lwip_fcntl(handle, F_SETFL, flags));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  FillSockAddrIpv4(@sa[0], hostAddr, port);
  Result := EspNet(lwip_bind(handle, @sa[0], 16));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendConnectUnix(handle: Integer; const path: string): Integer;
{ lwIP has no AF_UNIX: there is no filesystem to hold a socket node. Reported
  as unsupported rather than failing obscurely at connect() time, so a caller
  can pick another backend. }
begin
  Result := PAL_NET_ENOTSUP;
end;

function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  FillSockAddrIpv4(@sa[0], hostAddr, port);
  Result := EspNet(lwip_connect(handle, @sa[0], 16));
  { lwIP reports EVERY RST as ECONNRESET, including the one answering our SYN.
    That is a refusal -- no connection existed to be reset -- and it is what
    Linux, and so the PAL contract, calls ECONNREFUSED. Measured on the S3: a
    connect to a closed 127.0.0.1 port read [Errno 104] until this line. }
  if Result = PAL_NET_ECONNRESET then Result := PAL_NET_ECONNREFUSED;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ IPv6 on ESP: lwIP can do it, but only when the IDF build has LWIP_IPV6
  enabled, and this backend has no way to ask. Rather than emit a sockaddr_in6
  that a v4-only lwIP would reject with a confusing errno, both entry points
  report PAL_ERR_UNSUPPORTED until someone builds and runs it on a device with
  IPv6 turned on. Refusing honestly beats a plausible-looking failure — see
  feature-pal-esp-posix-fd-semantics for the same discipline elsewhere in this
  backend. }
function PalBackendBindIpv6(handle: Integer; const addr: TPalIn6Addr;
                            port, scopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendConnectIpv6(handle: Integer; const addr: TPalIn6Addr;
                               port, scopeId: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

{ Same rule as bind/connect above: refuse honestly rather than hand lwIP a
  sockaddr_in6 it may not have been built to understand. A zeroed peer address
  reported as real would be worse than no peer address. }
function PalBackendAcceptIpv6(handle: Integer; var outAddr: TPalIn6Addr;
                              var outPort, outScopeId: Integer): Integer;
var i: Integer;
begin
  for i := 0 to 15 do outAddr.Bytes[i] := 0;
  outPort := 0;
  outScopeId := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSendToIpv6(handle: Integer; buf: Pointer; len: Integer;
                              const addr: TPalIn6Addr; port, scopeId: Integer; flags: Integer): Int64;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendRecvFromIpv6(handle: Integer; buf: Pointer; len: Integer;
                                var outAddr: TPalIn6Addr; var outPort, outScopeId: Integer; flags: Integer): Int64;
var i: Integer;
begin
  for i := 0 to 15 do outAddr.Bytes[i] := 0;
  outPort := 0;
  outScopeId := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendListen(handle, backlog: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_listen(handle, backlog));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendAccept(handle: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_accept(handle, nil, nil));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ PAL_MSG_* -> lwIP MSG_*. THE NUMBERS DO NOT AGREE WITH LINUX'S AND THAT IS
  THE WHOLE POINT OF THIS FUNCTION: lwIP MSG_PEEK is 1 where Linux's is 2, and
  lwIP's 2 is MSG_WAITALL, which its own header marks "Unimplemented". A PAL
  that passed Linux numbers through would turn a peek into a silently ignored
  flag -- the data consumed, the second peek blocking forever, which is exactly
  the bug the flags parameter was added to fix.
  Values read from
  /home/neo/esp/esp-idf/components/lwip/lwip/src/include/lwip/sockets.h:269-274
  on 2026-09-04, not recalled.

  OOB IS REFUSED RATHER THAN TRANSLATED. lwIP defines MSG_OOB (0x04) and marks
  it "Unimplemented" in the same breath, so passing it through would return
  success having ignored the caller entirely. ESP is not a Unix and the PAL's
  standing answer to that is PAL_ERR_UNSUPPORTED, not a wrong answer -- 33
  other PAL entries already refuse deliberately. MSG_WAITALL is refused for the
  same reason and from the same header line. }
const
  LWIP_MSG_PEEK     = $01;
  LWIP_MSG_DONTWAIT = $08;

function XlatMsgFlags(flags: Integer; var outFlags: Integer): Integer;
begin
  outFlags := 0;
  if (flags and not (PAL_MSG_PEEK or PAL_MSG_DONTWAIT)) <> 0 then
  begin
    if (flags and not PAL_MSG_ALL) <> 0 then XlatMsgFlags := PAL_ERR_INVALID
    else XlatMsgFlags := PAL_ERR_UNSUPPORTED;
    Exit;
  end;
  if (flags and PAL_MSG_PEEK) <> 0 then outFlags := outFlags or LWIP_MSG_PEEK;
  if (flags and PAL_MSG_DONTWAIT) <> 0 then outFlags := outFlags or LWIP_MSG_DONTWAIT;
  XlatMsgFlags := 0;
end;

function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
var f, rc: Integer;
begin
  rc := XlatMsgFlags(flags, f);
  if rc <> 0 then begin Result := rc; Exit; end;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_recv(handle, buf, len, f));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

{ No MSG_NOSIGNAL here, unlike the posix backend, and not by omission: lwIP
  raises no SIGPIPE at all -- it defines MSG_NOSIGNAL(0x20) only to mark it
  "Unimplemented". A closed peer already yields an error return here. }
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer; flags: Integer): Int64;
var f, rc: Integer;
begin
  rc := XlatMsgFlags(flags, f);
  if rc <> 0 then begin Result := rc; Exit; end;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_send(handle, buf, len, f));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendShutdown(handle, how: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_shutdown(handle, how));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSocketClose(handle: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_close(handle));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSendToIpv4(handle: Integer; buf: Pointer; len: Integer; hostAddr: LongWord; port: Integer; flags: Integer): Int64;
var sa: array[0..15] of Byte; f, rc: Integer;
begin
  rc := XlatMsgFlags(flags, f);
  if rc <> 0 then begin Result := rc; Exit; end;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  FillSockAddrIpv4(@sa[0], hostAddr, port);
  Result := EspNet(lwip_sendto(handle, buf, len, f, @sa[0], 16));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRecvFromIpv4(handle: Integer; buf: Pointer; len: Integer; var outAddr: LongWord; var outPort: Integer; flags: Integer): Int64;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i, f, rc: Integer;
begin
  outAddr := 0;
  outPort := 0;
  rc := XlatMsgFlags(flags, f);
  if rc <> 0 then begin Result := rc; Exit; end;
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
  Result := EspNet(lwip_recvfrom(handle, buf, len, f, @sa[0], @addrlen));
  if Result >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  outAddr := 0;
  outPort := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendPoll(handle, events, timeoutMs: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var pfd: array[0..1] of Integer;
begin
  pfd[0] := handle;
  pfd[1] := events and $FFFF;
  Result := EspNet(lwip_poll(@pfd[0], 1, timeoutMs));
  if Result > 0 then
    Result := (pfd[1] shr 16) and $FFFF;
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

{ Set-shaped poll. Under IDF this is lwip_poll over the caller's own array —
  lwIP's struct pollfd has the same int-then-two-shorts layout as Linux's, so
  nothing is repacked. Bare answers PAL_ERR_UNSUPPORTED like every other socket
  entry there: ESP is not a Unix, and a refusal beats a wrong answer. }
function PalBackendPollSet(fds: Pointer; nfds: Integer; timeoutMs: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  Result := EspNet(lwip_poll(fds, nfds, timeoutMs));
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendGetSockError(handle: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var
  err, optlen: Integer;
  rc: Integer;
begin
  err := 0;
  optlen := 4;
  rc := EspNet(lwip_getsockopt(handle, SOL_SOCKET, SO_ERROR, @err, @optlen));
  if rc < 0 then
    Result := rc
  else
    Result := -NewlibToLinuxErrno(err);   { SO_ERROR holds a NEWLIB errno too }
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendGetSockNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Integer;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
  rc := EspNet(lwip_getsockname(handle, @sa[0], @addrlen));
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := rc;
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  outAddr := 0;
  outPort := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendGetPeerNameIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Integer;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
  rc := EspNet(lwip_getpeername(handle, @sa[0], @addrlen));
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := rc;
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  outAddr := 0;
  outPort := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendGetSockOpt(handle, level, optname: Integer; valPtr: Pointer; lenPtr: Pointer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_getsockopt(handle, level, optname, valPtr, lenPtr));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendIoctl(handle: Integer; cmd: NativeInt; argp: Pointer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := EspNet(lwip_ioctl(handle, LongWord(cmd), argp));
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendAcceptIpv4(handle: Integer; var outAddr: LongWord; var outPort: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
var
  sa: array[0..15] of Byte;
  addrlen: Integer;
  i: Integer;
  rc: Integer;
begin
  for i := 0 to 15 do sa[i] := 0;
  addrlen := 16;
  rc := EspNet(lwip_accept(handle, @sa[0], @addrlen));
  outAddr := 0;
  outPort := 0;
  if rc >= 0 then
    ParseSockAddrIpv4(@sa[0], outAddr, outPort);
  Result := rc;
end;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
begin
  outAddr := 0;
  outPort := 0;
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendMonotonicMillis: Int64;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := esp_timer_get_time div 1000;
{$else}  { NOT COMPILED ON ESP. PXX_PAL_ESP_IDF_TARGET is defined for both CPU_XTENSA and CPU_RISCV32 -- see the top of this unit -- so on every ESP target the ifdef arm above is taken and THIS arm is dead source: it is the host-build fallback. A PAL_ERR_UNSUPPORTED below is NOT a refusal the device can reach, and must not be counted as one. }
  Result := 0;
{$endif}
end;

procedure PalBackendYield;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  vTaskDelay(1);
{$endif}
end;

function PalBackendFork: Integer;
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


function PalBackendSetPgid(pid, pgid: Integer): Integer;
{ No process groups -- the same absence setsid and getsid refuse for. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendGetPgid(pid: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;


function PalBackendAlarm(seconds: LongWord): Integer;
{ No SIGALRM to deliver -- FreeRTOS has no POSIX signals, so a timer that could
  be armed would have nothing to raise. Refusing says so; returning 0 would
  claim an alarm was set. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetHostname(name: PChar; len: Integer): Integer;
{ No kernel-wide hostname; the IDF network stack carries its own per-interface
  name, which is a different thing under the same word. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSetGroups(count: Integer; list: Pointer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

function PalBackendSigTimedWait(setPtr: Pointer; setSize, sec, nsec: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;


function PalBackendSigProcMask(how: Integer; setPtr, oldSetPtr: Pointer; setSize: Integer): Integer;
{ No POSIX signals here, so there is no mask to change. }
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

end.
