{ SPDX-License-Identifier: Zlib }
unit mimic_socket;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `socket`, the IPv4 TCP subset, over this RTL's PAL socket layer
  (lib/rtl/platform.pas). The same unit serves a desktop program (the POSIX
  backend) and an ESP one (the lwIP backend), which is the point: a NilPy HTTP
  server written against CPython's names runs on both.

  `import socket` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, as mimic_urllib_request does; `--no-shims` turns it into an error.

  WHAT WORKS: socket(AF_INET, SOCK_STREAM); bind((host, port)), listen,
  accept -> (conn, (ip, port)), connect((host, port)), recv, send, sendall,
  close, setsockopt(SOL_SOCKET, SO_REUSEADDR, 1), setblocking, getsockname,
  fileno, and `with`. A host is a dotted quad, '' / '0.0.0.0' (any) or
  'localhost'.

  WHAT IT REFUSES, loudly: any family but AF_INET and any type but
  SOCK_STREAM (OSError at construction, not a socket that quietly is TCP);
  a host name other than 'localhost' (there is no resolver here -- CPython
  would look it up, and guessing is worse than refusing); settimeout with a
  positive value (the PAL has no per-socket timeout; accepting the number and
  blocking forever would turn "give up after 2 s" into "hang"). settimeout(None)
  and settimeout(0) are the blocking and non-blocking modes and are honoured.

  ERRORS are OSError, as in CPython, and a non-blocking call with nothing to
  do raises BlockingIOError, a subclass of it -- so `except OSError:` catches
  both, exactly as there. `socket.error` is OSError, as in CPython 3.

  The constants are CPython-on-Linux's values, because they are what a
  program prints; they are mapped to the PAL's own at each call, never passed
  through, so the ESP backend's lwIP numbering is never exposed. }

interface

uses pylib, sysutils, platform;

const
  AF_INET      = 2;
  SOCK_STREAM  = 1;
  SOL_SOCKET   = 1;
  SO_REUSEADDR = 2;
  SHUT_RD      = 0;
  SHUT_WR      = 1;
  SHUT_RDWR    = 2;

type
  BlockingIOError = class(OSError) end;
  error = OSError;

  socket = class
  private
    FHandle: Integer;
    FBlocking: Boolean;
  public
    constructor Create(family: Integer = AF_INET; type_: Integer = SOCK_STREAM;
      proto: Integer = 0);
    procedure bind(const address: TPyList);
    procedure listen(backlog: Integer = 5);
    function accept: TPyList;
    procedure connect(const address: TPyList);
    function recv(bufsize: Integer): TPyBytes;
    function send(data: TPyBytes): Integer;
    procedure sendall(data: TPyBytes);
    procedure setsockopt(level, optname, value: Integer);
    procedure setblocking(flag: Boolean);
    procedure settimeout(const value: Variant);
    function getsockname: TPyList;
    procedure shutdown(how: Integer);
    procedure close;
    function fileno: Integer;
    function __enter__: socket;
    procedure __exit__(const a, b, c: Variant);
  end;

implementation

{ PAL error codes are negative errnos in the Linux numbering on every backend. }
procedure Fail(const what: AnsiString; rc: Int64);
begin
  if (rc = PAL_NET_EAGAIN) or (rc = PAL_NET_EINPROGRESS) then
    raise BlockingIOError.Create('[Errno 11] Resource temporarily unavailable');
  raise OSError.Create('[Errno ' + IntToStr(-rc) + '] ' + what);
end;

function IpText(a: LongWord): AnsiString;
begin
  IpText := IntToStr((a shr 24) and 255) + '.' + IntToStr((a shr 16) and 255) + '.' +
            IntToStr((a shr 8) and 255) + '.' + IntToStr(a and 255);
end;

{ '' / '0.0.0.0' / 'localhost' / a dotted quad -> host-order address. }
function HostAddr(const host: AnsiString): LongWord;
var i, part, dots: Integer; acc: LongWord; ok: Boolean;
begin
  if (host = '') or (host = '0.0.0.0') then begin HostAddr := PAL_NET_IP_ANY; Exit; end;
  if host = 'localhost' then begin HostAddr := PAL_NET_IP_LOOPBACK; Exit; end;
  acc := 0; part := -1; dots := 0; ok := True;
  for i := 1 to Length(host) do
    if (host[i] >= '0') and (host[i] <= '9') then
    begin
      if part < 0 then part := 0;
      part := part * 10 + Ord(host[i]) - Ord('0');
      if part > 255 then ok := False;
    end
    else if (host[i] = '.') and (part >= 0) then
    begin
      acc := (acc shl 8) or LongWord(part);
      part := -1;
      dots := dots + 1;
    end
    else
      ok := False;
  if (not ok) or (dots <> 3) or (part < 0) then
    raise OSError.Create('socket: cannot resolve host ''' + host +
      ''' (only dotted quads and localhost; there is no resolver here)');
  HostAddr := (acc shl 8) or LongWord(part);
end;

procedure SplitAddress(const address: TPyList; var addr: LongWord; var port: Integer);
var h: AnsiString;
begin
  if address.count <> 2 then
    raise OSError.Create('socket: an AF_INET address is a (host, port) pair');
  h := address.at(0);
  port := address.at(1);
  addr := HostAddr(h);
end;

function AddrPair(addr: LongWord; port: Integer): TPyList;
var l: TPyList; v: Variant;
begin
  l := TPyList.Create;
  v := IpText(addr);
  l.append(v);
  v := port;
  l.append(v);
  AddrPair := pylist_mark_tuple(l);   { tuple(l) would COPY and strand l }
end;

constructor socket.Create(family: Integer; type_: Integer; proto: Integer);
begin
  if family <> AF_INET then
    raise OSError.Create('socket: only AF_INET is supported');
  if type_ <> SOCK_STREAM then
    raise OSError.Create('socket: only SOCK_STREAM is supported');
  FBlocking := True;
  FHandle := PalSocket(PAL_NET_AF_INET, PAL_NET_SOCK_STREAM, 0);
  if FHandle < 0 then Fail('socket', FHandle);
end;

procedure socket.bind(const address: TPyList);
var addr: LongWord; port, rc: Integer;
begin
  SplitAddress(address, addr, port);
  rc := PalBindIpv4(FHandle, addr, port);
  if rc < 0 then Fail('bind', rc);
end;

procedure socket.listen(backlog: Integer);
var rc: Integer;
begin
  rc := PalListen(FHandle, backlog);
  if rc < 0 then Fail('listen', rc);
end;

function socket.accept: TPyList;
var h, port: Integer; addr: LongWord; conn: socket; l: TPyList;
begin
  addr := 0; port := 0;
  h := PalAcceptIpv4(FHandle, addr, port);
  if h < 0 then Fail('accept', h);
  conn := socket.Create;
  PalSocketClose(conn.FHandle);   { the fresh one Create made; take the accepted one }
  conn.FHandle := h;
  l := TPyList.Create;
  l.append(TObject(conn));
  PXXObjRelease(Pointer(conn));   { the list holds it now }
  l.append(TObject(AddrPair(addr, port)));
  accept := pylist_mark_tuple(l);
end;

procedure socket.connect(const address: TPyList);
var addr: LongWord; port, rc: Integer;
begin
  SplitAddress(address, addr, port);
  rc := PalConnectIpv4(FHandle, addr, port);
  if rc < 0 then Fail('connect', rc);
end;

function socket.recv(bufsize: Integer): TPyBytes;
var r: TPyBytes; got: Int64;
begin
  if bufsize < 0 then raise OSError.Create('recv: negative buffersize');
  r := TPyBytes.Create(bufsize);
  got := 0;
  if bufsize > 0 then got := PalRecv(FHandle, r.FData, bufsize);
  if got < 0 then Fail('recv', got);
  r.FLen := got;
  recv := r;
end;

function socket.send(data: TPyBytes): Integer;
var sent: Int64;
begin
  if data.FLen = 0 then begin send := 0; Exit; end;
  sent := PalSend(FHandle, data.FData, data.FLen);
  if sent < 0 then Fail('send', sent);
  send := sent;
end;

procedure socket.sendall(data: TPyBytes);
var done, sent: Int64;
begin
  done := 0;
  while done < data.FLen do
  begin
    sent := PalSend(FHandle, PByte(data.FData) + done, data.FLen - done);
    if sent < 0 then Fail('sendall', sent);
    done := done + sent;
  end;
end;

procedure socket.setsockopt(level, optname, value: Integer);
var rc: Integer;
begin
  if (level = SOL_SOCKET) and (optname = SO_REUSEADDR) then
  begin
    rc := PalSetSocketReuseAddr(FHandle, value);
    if rc < 0 then Fail('setsockopt', rc);
  end
  else
    raise OSError.Create('setsockopt: only (SOL_SOCKET, SO_REUSEADDR) is supported');
end;

procedure socket.setblocking(flag: Boolean);
var rc, nb: Integer;
begin
  if flag then nb := 0 else nb := 1;
  rc := PalSetSocketNonBlocking(FHandle, nb);
  if rc < 0 then Fail('setblocking', rc);
  FBlocking := flag;
end;

procedure socket.settimeout(const value: Variant);
var f: Double;
begin
  if pystr_of(value) = 'None' then begin setblocking(True); Exit; end;
  f := value;
  if f = 0 then begin setblocking(False); Exit; end;
  raise OSError.Create('settimeout: only None (blocking) and 0 (non-blocking) are supported; ' +
    'the platform layer has no per-socket timeout');
end;

function socket.getsockname: TPyList;
var addr: LongWord; port, rc: Integer;
begin
  addr := 0; port := 0;
  rc := PalGetSockNameIpv4(FHandle, addr, port);
  if rc < 0 then Fail('getsockname', rc);
  getsockname := AddrPair(addr, port);
end;

procedure socket.shutdown(how: Integer);
var rc: Integer;
begin
  rc := PalShutdown(FHandle, how);
  if rc < 0 then Fail('shutdown', rc);
end;

procedure socket.close;
begin
  if FHandle >= 0 then PalSocketClose(FHandle);
  FHandle := -1;
end;

function socket.fileno: Integer;
begin
  fileno := FHandle;
end;

function socket.__enter__: socket;
begin
  __enter__ := Self;
end;

procedure socket.__exit__(const a, b, c: Variant);
begin
  close;
end;

end.
