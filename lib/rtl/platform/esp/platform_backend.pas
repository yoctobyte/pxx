unit platform_backend;
{ ESP-IDF/FreeRTOS PAL backend selected by -Fulib/rtl/platform/esp. }

interface

uses platform_types;

function PalBackendPlatform: Integer;
function PalBackendHasFiles: Boolean;
function PalBackendHasSockets: Boolean;
function PalBackendHasThreads: Boolean;
function PalBackendHasDynlib: Boolean;

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
function PalBackendGetDents64(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendStat(path: PChar; var info: TPalFileStat): Integer;
function PalBackendStatAt(dirHandle: Integer; path: PChar; var info: TPalFileStat): Integer;

function PalBackendSocket(domain, kind, proto: Integer): Integer;
function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
function PalBackendListen(handle, backlog: Integer): Integer;
function PalBackendAccept(handle: Integer): Integer;
function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
function PalBackendShutdown(handle, how: Integer): Integer;
function PalBackendSocketClose(handle: Integer): Integer;

function PalBackendMonotonicMillis: Int64;
procedure PalBackendYield;

function PalBackendVfork: Integer;
function PalBackendExecve(path: PChar; argv, envp: Pointer): Integer;
function PalBackendPipe2(var pipefd: array of Integer; flags: Integer): Integer;
function PalBackendDup2(oldFd, newFd: Integer): Integer;
function PalBackendWait4(pid: Integer; wstatus: Pointer; options: Integer; rusage: Pointer): Integer;
function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;

implementation

const
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
  SOL_SOCKET = 1;
  SO_REUSEADDR = 2;
  F_SETFL = 4;
  O_NONBLOCK = 1;

type
  PB = ^Byte;

{$ifdef CPU_XTENSA}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_PAL_ESP_IDF_TARGET}{$endif}

{$ifdef PXX_PAL_ESP_IDF_TARGET}
procedure vTaskDelay(ticks: Integer); external;
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

function PalBackendPlatform: Integer;
begin
  Result := PAL_PLATFORM_ESP_IDF;
end;

function PalBackendHasFiles: Boolean;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalBackendHasSockets: Boolean;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalBackendHasThreads: Boolean;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := True;
{$else}
  Result := False;
{$endif}
end;

function PalBackendHasDynlib: Boolean;
begin
  Result := False;
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
{$else}
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendRead(handle: Integer; buf: Pointer; len: Integer): Int64;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  if handle <= PAL_STDERR then
    Result := PAL_ERR_UNSUPPORTED
  else
    Result := fread(buf, 1, len, Pointer(handle));
end;
{$else}
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendWrite(handle: Integer; buf: Pointer; len: Integer): Int64;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  if handle <= PAL_STDERR then
    Result := PAL_ERR_UNSUPPORTED
  else
    Result := fwrite(buf, 1, len, Pointer(handle));
end;
{$else}
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
{$else}
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
{$else}
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendClose(handle: Integer): Integer;
{$ifdef PXX_PAL_ESP_IDF_TARGET}
begin
  if handle <= PAL_STDERR then
    Result := PAL_ERR_UNSUPPORTED
  else
    Result := fclose(Pointer(handle));
end;
{$else}
begin
  Result := PAL_ERR_UNSUPPORTED;
end;
{$endif}

function PalBackendDelete(path: PChar): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := remove(path);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRename(oldPath, newPath: PChar): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := rename(oldPath, newPath);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendMkdir(path: PChar; mode: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := mkdir(path, mode);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRmdir(path: PChar): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := rmdir(path);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
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

function PalBackendSocket(domain, kind, proto: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_socket(domain, kind, proto);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSetSocketReuseAddr(handle, enabled: Integer): Integer;
var one: Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  one := enabled;
  Result := lwip_setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, @one, 4);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSetSocketNonBlocking(handle, enabled: Integer): Integer;
var flags: Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  if enabled <> 0 then flags := O_NONBLOCK else flags := 0;
  Result := lwip_fcntl(handle, F_SETFL, flags);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendBindIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  FillSockAddrIpv4(@sa[0], hostAddr, port);
  Result := lwip_bind(handle, @sa[0], 16);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendConnectIpv4(handle: Integer; hostAddr: LongWord; port: Integer): Integer;
var sa: array[0..15] of Byte;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  FillSockAddrIpv4(@sa[0], hostAddr, port);
  Result := lwip_connect(handle, @sa[0], 16);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendListen(handle, backlog: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_listen(handle, backlog);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendAccept(handle: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_accept(handle, nil, nil);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendRecv(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_recv(handle, buf, len, 0);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSend(handle: Integer; buf: Pointer; len: Integer): Int64;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_send(handle, buf, len, 0);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendShutdown(handle, how: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_shutdown(handle, how);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendSocketClose(handle: Integer): Integer;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := lwip_close(handle);
{$else}
  Result := PAL_ERR_UNSUPPORTED;
{$endif}
end;

function PalBackendMonotonicMillis: Int64;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  Result := esp_timer_get_time div 1000;
{$else}
  Result := 0;
{$endif}
end;

procedure PalBackendYield;
begin
{$ifdef PXX_PAL_ESP_IDF_TARGET}
  vTaskDelay(1);
{$endif}
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

function PalBackendVforkAndExec(path: PChar; argv, envp: Pointer; stdinReadFd, stdinWriteFd, stdoutReadFd, stdoutWriteFd: Integer): Integer;
begin
  Result := PAL_ERR_UNSUPPORTED;
end;

end.
